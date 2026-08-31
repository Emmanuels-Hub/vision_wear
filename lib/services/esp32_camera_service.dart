import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/app_mode.dart';
import '../models/app_settings.dart';
import '../models/connection_state.dart';
import 'device_discovery_service.dart';
import 'mjpeg_parser.dart';
import 'network_binding_service.dart';

/// Owns the link to the camera and keeps it alive.
///
/// The previous implementation opened a fresh TCP connection per frame with
/// `http.get`, drove it from a `Timer.periodic` that fired whether or not the
/// last request had finished, and shut polling down permanently on the first
/// error. That combination produced all three reported symptoms: latency from
/// the per-frame handshake, request pile-up under load, and a link that never
/// came back after a momentary drop.
///
/// This version:
///   * prefers one long-lived MJPEG connection (no per-frame handshake),
///   * falls back to `/capture` polling over a keep-alive client with an
///     in-flight guard,
///   * long-polls `/events` on a separate connection so button presses arrive
///     in milliseconds and keep working even if the camera itself is wedged,
///   * supervises the link: a stall watchdog plus capped exponential backoff
///     that retries indefinitely until told to stop.
class Esp32CameraService {
  Esp32CameraService({
    DeviceDiscoveryService? discoveryService,
    NetworkBindingService? networkBinding,
  })  : _discovery = discoveryService ?? DeviceDiscoveryService(),
        _network = networkBinding ?? NetworkBindingService();

  final DeviceDiscoveryService _discovery;

  /// Keeps the app's sockets on the WiFi interface. Without this, Android
  /// routes requests for the camera over mobile data and they never arrive.
  final NetworkBindingService _network;

  /// Exposed so the connection screen can explain a failure in terms of what
  /// the phone's networking is actually doing.
  Future<NetworkRouting> networkRouting() => _network.status();

  // Two clients so a stalled frame read can never delay a button event.
  http.Client _frameClient = http.Client();
  http.Client _eventClient = http.Client();

  CameraController? _phoneController;
  List<CameraDescription>? _cameras;

  StreamSubscription<List<int>>? _mjpegSub;
  StreamSubscription<DiscoveredDevice>? _discoverySub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  Timer? _watchdogTimer;
  Timer? _reconnectTimer;
  Timer? _pollTimer;

  final MjpegParser _mjpegParser = MjpegParser();

  AppSettings _settings = const AppSettings();
  CameraConnectionInfo _connection = const CameraConnectionInfo();
  Uint8List? _latestFrame;

  /// True once the caller has asked to be connected. Everything the supervisor
  /// does is gated on this, so a user-initiated disconnect is never undone by
  /// a pending retry.
  bool _wantConnection = false;
  bool _establishing = false;
  bool _pollInFlight = false;
  bool _eventLoopRunning = false;
  int _reconnectAttempts = 0;

  final Set<int> _seenEventIds = <int>{};
  DateTime? _lastFrameAt;
  final List<DateTime> _frameTimestamps = [];

  final _frameController = StreamController<Uint8List>.broadcast();
  final _connectionController =
      StreamController<CameraConnectionInfo>.broadcast();
  final _buttonEventController = StreamController<ButtonEvent>.broadcast();

  Stream<Uint8List> get frameStream => _frameController.stream;
  Stream<CameraConnectionInfo> get connectionStream =>
      _connectionController.stream;
  Stream<ButtonEvent> get buttonEventStream => _buttonEventController.stream;

  CameraConnectionInfo get connection => _connection;
  Uint8List? get latestFrame => _latestFrame;
  CameraController? get phoneController => _phoneController;

  /// True when frames come from the phone's own camera rather than the ESP32.
  /// The UI branches on this to decide between the native YOLOView widget and
  /// the ESP32 frame pipeline.
  bool get isUsingPhoneCamera => _settings.usePhoneCamera;

  void updateSettings(AppSettings settings) {
    final needsRestart =
        _wantConnection &&
        (settings.esp32Ip != _settings.esp32Ip ||
            settings.usePhoneCamera != _settings.usePhoneCamera ||
            settings.preferMjpegStream != _settings.preferMjpegStream ||
            settings.streamPort != _settings.streamPort ||
            settings.controlPort != _settings.controlPort ||
            settings.eventsPort != _settings.eventsPort);

    _settings = settings;

    if (needsRestart) {
      // Rebuild rather than silently keep serving frames from the old address.
      unawaited(connect());
    }
  }

  // ===================== Public API =====================

  /// One-shot reachability check used by the connection screen.
  Future<bool> testConnection(String ip, String capturePath) async {
    final client = http.Client();
    try {
      final url = 'http://$ip:${_settings.controlPort}$capturePath';
      final response = await client
          .get(Uri.parse(url))
          .timeout(
            const Duration(milliseconds: AppConstants.captureTimeoutMs),
          );
      return response.statusCode == 200 && response.bodyBytes.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> connect() async {
    // Drop any pending retry so it cannot fire on top of this attempt.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _teardownTransport();
    _wantConnection = true;
    _reconnectAttempts = 0;
    _startConnectivityWatch();
    await _establish();
  }

  Future<void> disconnect() async {
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardownTransport();
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _discoverySub?.cancel();
    _discoverySub = null;
    await _discovery.stopBeaconListener();

    await _network.releaseMulticastLock();
    await _network.unbind();

    _latestFrame = null;
    _seenEventIds.clear();
    _frameTimestamps.clear();
    _connection = const CameraConnectionInfo();
    _emitConnection();
  }

  /// Pushes a mode change to the device so the physical button and the phone
  /// UI cannot drift apart.
  Future<bool> setDeviceMode(AppMode mode) async {
    if (_settings.usePhoneCamera) return false;
    try {
      final response = await _frameClient
          .get(Uri.parse(_settings.modeUrl(mode.deviceIndex)))
          .timeout(
            const Duration(milliseconds: AppConstants.captureTimeoutMs),
          );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<DeviceStatus?> fetchStatus() async {
    if (_settings.usePhoneCamera) return null;
    try {
      final response = await _frameClient
          .get(Uri.parse(_settings.statusUrl))
          .timeout(
            const Duration(milliseconds: AppConstants.captureTimeoutMs),
          );
      if (response.statusCode != 200) return null;
      return DeviceStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Hands the device credentials for a normal WiFi network. Once it joins,
  /// the phone can stay on a network with internet instead of being stranded
  /// on the camera's own access point.
  Future<bool> provisionDeviceWifi(String ssid, String password) async {
    try {
      final uri = Uri.parse('${_settings.baseUrl}/wifi').replace(
        queryParameters: {'ssid': ssid, 'pass': password},
      );
      final response = await _frameClient
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ===================== Connection supervisor =====================

  Future<void> _establish() async {
    if (_establishing || !_wantConnection) return;
    _establishing = true;

    try {
      if (_settings.usePhoneCamera) {
        // The phone camera needs no network, and staying bound to a WiFi with
        // no internet would cut the rest of the app off for no reason.
        await _network.unbind();
        await _network.releaseMulticastLock();
        await _connectPhoneCamera();
        return;
      }

      // Do this before any request goes out, including discovery.
      await _network.bindToWifi();
      await _network.acquireMulticastLock();

      final isRetry = _reconnectAttempts > 0;
      _updateConnection(
        status: isRetry
            ? ConnectionStatus.reconnecting
            : ConnectionStatus.connecting,
        source: CameraSource.esp32,
        message: isRetry
            ? 'Reconnecting to camera...'
            : 'Connecting to camera...',
      );

      final ip = await _resolveDeviceIp();
      if (ip == null) {
        _failAndRetry('Cannot find the ESP32-CAM on this network');
        return;
      }

      if (ip != _settings.esp32Ip) {
        // The device moved (AP -> home WiFi, or DHCP handed it a new lease).
        _settings = _settings.copyWith(esp32Ip: ip);
      }

      _mjpegParser.reset();
      _frameTimestamps.clear();
      // Seed from connection time, not null. If it were null the watchdog would
      // skip its check, and a stream that opens but never delivers a frame
      // would leave the app waiting forever.
      _lastFrameAt = DateTime.now();

      final started = _settings.preferMjpegStream
          ? await _startMjpegStream()
          : false;

      if (started) {
        _updateConnection(
          status: ConnectionStatus.connected,
          source: CameraSource.esp32,
          transport: FrameTransport.mjpegStream,
          deviceIp: ip,
          message: 'Connected to ESP32-CAM',
          reconnectAttempts: 0,
        );
      } else {
        // Stream refused or unsupported: fall back to polling before giving up.
        final reachable = await _probeCapture();
        if (!reachable) {
          _failAndRetry('Cannot reach ESP32 at $ip');
          return;
        }
        _startCapturePolling();
        _updateConnection(
          status: ConnectionStatus.connected,
          source: CameraSource.esp32,
          transport: FrameTransport.pollCapture,
          deviceIp: ip,
          message: 'Connected to ESP32-CAM (polling)',
          reconnectAttempts: 0,
        );
      }

      _reconnectAttempts = 0;
      _startEventLoop();
      _startWatchdog();
      unawaited(_syncDeviceMode());
    } finally {
      _establishing = false;
    }
  }

  Future<String?> _resolveDeviceIp() async {
    final preferred = _settings.esp32Ip;

    if (!_settings.autoDiscover) {
      return preferred.isNotEmpty ? preferred : null;
    }

    _updateConnection(
      status: _reconnectAttempts > 0
          ? ConnectionStatus.reconnecting
          : ConnectionStatus.discovering,
      message: 'Looking for the camera...',
    );

    // Keep the beacon listener running for the whole session so an address
    // change is noticed even while we are connected.
    await _startDiscoveryWatch();

    final device = await _discovery.discover(
      preferredIp: preferred,
      // A full subnet sweep is slow; only worth it on a first connect, not on
      // every reconnect attempt.
      allowSubnetScan: _reconnectAttempts <= 1,
    );

    return device?.ip ?? (preferred.isNotEmpty ? preferred : null);
  }

  Future<void> _startDiscoveryWatch() async {
    if (_discoverySub != null) return;
    await _discovery.startBeaconListener();
    _discoverySub = _discovery.deviceStream.listen((device) {
      if (!_wantConnection || _settings.usePhoneCamera) return;
      if (device.ip == _settings.esp32Ip) return;

      // The device announced a different address than the one we are using.
      // Adopt it and rebuild, which is how the app follows the board when it
      // hops between its own AP and the home network.
      debugPrint('Discovery: device moved to ${device.ip}, reconnecting');
      _settings = _settings.copyWith(
        esp32Ip: device.ip,
        controlPort: device.controlPort,
        streamPort: device.streamPort,
        eventsPort: device.eventsPort,
      );
      unawaited(_restart('camera address changed'));
    });
  }

  void _failAndRetry(String message) {
    _updateConnection(
      status: ConnectionStatus.error,
      source: CameraSource.esp32,
      transport: FrameTransport.none,
      message: message,
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_wantConnection || !_settings.autoReconnect) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;

    // Capped exponential backoff. Starts at 400 ms because a blind wearer
    // standing at a kerb cannot wait out a 30 s backoff.
    final delayMs = math.min(
      AppConstants.reconnectMaxDelayMs,
      AppConstants.reconnectInitialDelayMs * (1 << math.min(_reconnectAttempts - 1, 4)),
    );

    _updateConnection(
      status: ConnectionStatus.reconnecting,
      message: 'Reconnecting (attempt $_reconnectAttempts)...',
      reconnectAttempts: _reconnectAttempts,
    );

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      _reconnectTimer = null;
      if (!_wantConnection) return;
      await _teardownTransport(keepSupervisor: true);
      await _establish();
    });
  }

  Future<void> _restart(String reason) async {
    if (!_wantConnection) return;
    debugPrint('Camera link restart: $reason');
    await _teardownTransport(keepSupervisor: true);
    await _establish();
  }

  /// Detects a link that is nominally up but has gone quiet — the half-open
  /// TCP socket left behind by a WiFi handover or an ESP32 reboot. Without
  /// this the app sits on a frozen last frame and reports "connected".
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_wantConnection || _settings.usePhoneCamera) return;
      if (_connection.status != ConnectionStatus.connected) return;

      final last = _lastFrameAt;
      if (last == null) return;

      final quietMs = DateTime.now().difference(last).inMilliseconds;
      if (quietMs > AppConstants.frameStallTimeoutMs) {
        _updateConnection(
          status: ConnectionStatus.reconnecting,
          message: 'Camera feed stalled, reconnecting...',
        );
        unawaited(_restart('no frames for ${quietMs}ms'));
      }
    });
  }

  /// Rebuilds the link when the phone changes network, rather than waiting for
  /// the stall watchdog to notice several seconds later.
  void _startConnectivityWatch() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (!_wantConnection || _settings.usePhoneCamera) return;
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) {
        _updateConnection(
          status: ConnectionStatus.reconnecting,
          message: 'Waiting for WiFi...',
        );
        return;
      }
      unawaited(_restart('network changed'));
    });
  }

  // ===================== MJPEG transport =====================

  Future<bool> _startMjpegStream() async {
    try {
      final request = http.Request('GET', Uri.parse(_settings.streamUrl));
      request.headers['Accept'] = 'multipart/x-mixed-replace';
      request.headers['Connection'] = 'keep-alive';

      final response = await _frameClient
          .send(request)
          .timeout(const Duration(milliseconds: AppConstants.captureTimeoutMs));

      if (response.statusCode != 200) {
        debugPrint('MJPEG stream returned ${response.statusCode}');
        return false;
      }

      _mjpegSub = response.stream.listen(
        (chunk) {
          final frames = _mjpegParser.addChunk(chunk);
          for (final frame in frames) {
            _emitFrame(frame);
          }
        },
        onError: (Object error) {
          if (!_wantConnection) return;
          _updateConnection(
            status: ConnectionStatus.reconnecting,
            message: 'Stream interrupted, reconnecting...',
          );
          unawaited(_restart('stream error: $error'));
        },
        onDone: () {
          if (!_wantConnection) return;
          unawaited(_restart('stream closed by device'));
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      debugPrint('MJPEG stream unavailable ($e), falling back to polling');
      return false;
    }
  }

  // ===================== /capture polling fallback =====================

  Future<bool> _probeCapture() async {
    try {
      final response = await _frameClient
          .get(Uri.parse(_settings.captureUrl))
          .timeout(
            const Duration(milliseconds: AppConstants.captureTimeoutMs),
          );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _emitFrame(response.bodyBytes);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _startCapturePolling() {
    _pollTimer?.cancel();
    final interval = math.max(50, _settings.frameIntervalMs);
    _pollTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
      // In-flight guard: the old code fired a new request every tick regardless
      // of whether the previous one had returned, which queued requests faster
      // than the ESP32 could answer them.
      if (_pollInFlight) return;
      unawaited(_fetchCaptureFrame());
    });
  }

  Future<void> _fetchCaptureFrame() async {
    if (_pollInFlight || !_wantConnection) return;
    _pollInFlight = true;

    final start = DateTime.now();
    try {
      final response = await _frameClient
          .get(Uri.parse(_settings.captureUrl))
          .timeout(
            const Duration(milliseconds: AppConstants.captureTimeoutMs),
          );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _emitFrame(
          response.bodyBytes,
          latencyMs: DateTime.now().difference(start).inMilliseconds,
        );
      }
    } catch (_) {
      // A single failed poll is not a disconnect — WiFi drops a packet all the
      // time. The watchdog decides when the link is genuinely gone.
    } finally {
      _pollInFlight = false;
    }
  }

  // ===================== Button events =====================

  /// Long-polls `/events`. The device holds the request open until a button is
  /// pressed, so the press reaches the phone in about the network round-trip
  /// time instead of waiting out a fixed poll interval.
  void _startEventLoop() {
    if (_eventLoopRunning || _settings.usePhoneCamera) return;
    _eventLoopRunning = true;
    unawaited(_eventLoop());
  }

  Future<void> _eventLoop() async {
    while (_wantConnection && !_settings.usePhoneCamera) {
      try {
        final uri = Uri.parse(_settings.eventsUrl).replace(
          queryParameters: {'wait': '${AppConstants.eventLongPollMs}'},
        );

        final response = await _eventClient
            .get(uri)
            .timeout(
              const Duration(
                milliseconds: AppConstants.eventRequestTimeoutMs,
              ),
            );

        if (response.statusCode == 200) {
          _handleEventPayload(response.body);
          continue; // straight back into the next long-poll
        }

        // Older firmware without long-poll support returns immediately; pace
        // ourselves so we do not spin.
        await Future.delayed(
          const Duration(milliseconds: AppConstants.buttonPollIntervalMs),
        );
      } catch (_) {
        if (!_wantConnection) break;
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    _eventLoopRunning = false;
  }

  void _handleEventPayload(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;

      // The device reports its own mode on every response, which lets the app
      // resynchronise even if it missed the mode_changed event itself.
      final deviceMode = map['device_mode'] as String?;
      if (deviceMode != null && deviceMode != _connection.deviceMode) {
        _updateConnection(deviceMode: deviceMode);
      }

      final events = map['events'] as List<dynamic>? ?? const [];
      for (final raw in events) {
        if (raw is! Map<String, dynamic>) continue;
        final event = ButtonEvent.fromJson(raw);
        if (event.action.isEmpty) continue;

        // The device clears its queue when it answers, but a retried request
        // after a timeout can redeliver. Dedupe so one press is not acted on
        // twice.
        if (event.id != 0) {
          if (_seenEventIds.contains(event.id)) continue;
          _seenEventIds.add(event.id);
          if (_seenEventIds.length > 256) {
            _seenEventIds.remove(_seenEventIds.first);
          }
        }

        if (!_buttonEventController.isClosed) {
          _buttonEventController.add(event);
        }
      }
    } catch (_) {
      // Malformed payload; the next poll will bring a clean one.
    }
  }

  Future<void> _syncDeviceMode() async {
    final status = await fetchStatus();
    if (status == null) return;
    _updateConnection(deviceMode: status.currentMode);
  }

  // ===================== Phone camera =====================
  //
  // Ownership rule, and the reason the preview used to come up black:
  //
  //   * In object-detection mode the native `YOLOView` widget opens the camera
  //     itself and runs inference on its own frames.
  //   * In OCR mode we need a still photo, which YOLOView cannot give us, so a
  //     `CameraController` opens the camera instead.
  //
  // Only one of the two may hold the device at a time. The old code created a
  // CameraController on connect() *and* left YOLOView mounted, so both fought
  // over the same sensor — on Android the second open fails and on iOS the
  // preview freezes. It also drove `takePicture()` from a Timer to fake a frame
  // stream, which fires the shutter, re-runs autofocus and stalls for hundreds
  // of milliseconds per frame.
  //
  // So: connecting the phone camera is now a no-op beyond a capability check,
  // and [openStillCamera] / [closeStillCamera] hand the sensor between the two
  // consumers explicitly.

  Future<void> _connectPhoneCamera() async {
    _updateConnection(
      status: ConnectionStatus.connecting,
      source: CameraSource.phone,
      message: 'Starting phone camera...',
    );

    try {
      _cameras ??= await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _updateConnection(
          status: ConnectionStatus.error,
          source: CameraSource.phone,
          message: 'No phone camera found',
        );
        return;
      }

      _updateConnection(
        status: ConnectionStatus.connected,
        source: CameraSource.phone,
        transport: FrameTransport.phoneCamera,
        message: 'Phone camera active',
      );
    } catch (e) {
      _updateConnection(
        status: ConnectionStatus.error,
        source: CameraSource.phone,
        message: 'Phone camera error: $e',
      );
    }
  }

  /// Opens a [CameraController] for still capture, used by OCR mode.
  ///
  /// The caller must have torn down any `YOLOView` first, otherwise this fails
  /// with a device-in-use error from the platform.
  Future<bool> openStillCamera() async {
    if (!_settings.usePhoneCamera) return false;
    final existing = _phoneController;
    if (existing != null && existing.value.isInitialized) return true;

    try {
      _cameras ??= await availableCameras();
      final cameras = _cameras;
      if (cameras == null || cameras.isEmpty) return false;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // `high` rather than `medium`: OCR accuracy is bounded by how many pixels
      // land on each glyph, and medium loses small print entirely.
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _phoneController = controller;
      _emitConnection();
      return true;
    } catch (e) {
      debugPrint('Still camera open failed: $e');
      _phoneController = null;
      return false;
    }
  }

  /// Releases the still-capture controller so `YOLOView` can take the sensor
  /// back when the user returns to object-detection mode.
  Future<void> closeStillCamera() async {
    final controller = _phoneController;
    _phoneController = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // Disposing a controller that already errored throws; nothing to do.
    }
    _emitConnection();
  }

  /// Takes one photo for OCR and returns its path, or null if unavailable.
  Future<String?> captureStill() async {
    final controller = _phoneController;
    if (controller == null || !controller.value.isInitialized) return null;
    if (controller.value.isTakingPicture) return null;
    try {
      final file = await controller.takePicture();
      return file.path;
    } catch (e) {
      debugPrint('Still capture failed: $e');
      return null;
    }
  }

  // ===================== Frame + state plumbing =====================

  void _emitFrame(Uint8List bytes, {int? latencyMs}) {
    final now = DateTime.now();
    _latestFrame = bytes;
    _lastFrameAt = now;

    // Rolling 2-second window, so the reported rate reflects what is happening
    // now rather than an average since connect.
    _frameTimestamps.add(now);
    _frameTimestamps.removeWhere(
      (t) => now.difference(t) > const Duration(seconds: 2),
    );
    final fps = _frameTimestamps.length / 2.0;

    _connection = _connection.copyWith(
      lastFrameTime: now,
      framesReceived: _connection.framesReceived + 1,
      latencyMs: latencyMs ?? _connection.latencyMs,
      fps: fps,
    );

    // A frame arriving is proof the link is healthy; promote out of
    // reconnecting so the UI settles.
    if (_connection.status != ConnectionStatus.connected) {
      _connection = _connection.copyWith(
        status: ConnectionStatus.connected,
        message: _connection.source == CameraSource.phone
            ? 'Phone camera active'
            : 'Connected to ESP32-CAM',
      );
    }

    if (!_frameController.isClosed) _frameController.add(bytes);
    _emitConnection();
  }

  void _updateConnection({
    ConnectionStatus? status,
    CameraSource? source,
    FrameTransport? transport,
    String? message,
    String? deviceIp,
    int? reconnectAttempts,
    String? deviceMode,
  }) {
    _connection = _connection.copyWith(
      status: status,
      source: source,
      transport: transport,
      message: message,
      deviceIp: deviceIp,
      reconnectAttempts: reconnectAttempts,
      deviceMode: deviceMode,
    );
    _emitConnection();
  }

  void _emitConnection() {
    if (!_connectionController.isClosed) {
      _connectionController.add(_connection);
    }
  }

  /// Tears down the frame transport. [keepSupervisor] preserves the watchdog,
  /// discovery listener and connectivity listener across a reconnect.
  Future<void> _teardownTransport({bool keepSupervisor = false}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;

    await _mjpegSub?.cancel();
    _mjpegSub = null;
    _mjpegParser.reset();

    if (!keepSupervisor) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }

    // Closing the client aborts any in-flight stream read. A fresh client also
    // guarantees we are not reusing a half-open pooled socket, which is what
    // makes a reconnect after a WiFi drop succeed on the first try.
    _frameClient.close();
    _frameClient = http.Client();

    if (!keepSupervisor) {
      _eventClient.close();
      _eventClient = http.Client();
    }

  }

  Future<void> dispose() async {
    await closeStillCamera();
    await _network.releaseMulticastLock();
    await _network.unbind();
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    await _teardownTransport();
    await _connectivitySub?.cancel();
    await _discoverySub?.cancel();
    _discovery.dispose();
    _eventClient.close();
    await _frameController.close();
    await _connectionController.close();
    await _buttonEventController.close();
  }
}
