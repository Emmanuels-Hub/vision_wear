import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/app_settings.dart';
import '../models/connection_state.dart';

class Esp32CameraService {
  Esp32CameraService();

  CameraController? _phoneController;
  List<CameraDescription>? _cameras;
  Timer? _pollTimer;
  Timer? _buttonPollTimer;
  AppSettings _settings = const AppSettings();
  CameraConnectionInfo _connection = const CameraConnectionInfo();
  Uint8List? _latestFrame;

  final _frameController = StreamController<Uint8List>.broadcast();
  final _connectionController =
      StreamController<CameraConnectionInfo>.broadcast();
  final _buttonEventController = StreamController<String>.broadcast();

  Stream<Uint8List> get frameStream => _frameController.stream;
  Stream<CameraConnectionInfo> get connectionStream =>
      _connectionController.stream;
  Stream<String> get buttonEventStream => _buttonEventController.stream;

  CameraConnectionInfo get connection => _connection;
  Uint8List? get latestFrame => _latestFrame;
  CameraController? get phoneController => _phoneController;

  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  Future<bool> testConnection(String ip, String capturePath) async {
    try {
      final url = 'http://$ip$capturePath';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 && response.bodyBytes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> connect() async {
    await disconnect();
    _updateConnection(
      status: ConnectionStatus.connecting,
      message: 'Connecting to camera...',
    );

    if (_settings.usePhoneCamera) {
      await _connectPhoneCamera();
    } else {
      await _connectEsp32();
    }
  }

  Future<void> _connectPhoneCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _updateConnection(
          status: ConnectionStatus.error,
          source: CameraSource.phone,
          message: 'No phone camera found',
        );
        return;
      }

      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _phoneController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _phoneController!.initialize();

      _pollTimer = Timer.periodic(
        Duration(milliseconds: _settings.frameIntervalMs),
        (_) => _capturePhoneFrame(),
      );
      await _capturePhoneFrame();

      _updateConnection(
        status: ConnectionStatus.connected,
        source: CameraSource.phone,
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

  Future<void> _capturePhoneFrame() async {
    if (_phoneController == null || !_phoneController!.value.isInitialized) {
      return;
    }

    try {
      final start = DateTime.now();
      final file = await _phoneController!.takePicture();
      final bytes = await file.readAsBytes();
      final latency = DateTime.now().difference(start).inMilliseconds;
      _emitFrame(bytes, latencyMs: latency);
    } catch (_) {}
  }

  Future<void> _connectEsp32() async {
    final reachable = await testConnection(
      _settings.esp32Ip,
      _settings.capturePath,
    );

    if (!reachable) {
      _updateConnection(
        status: ConnectionStatus.error,
        source: CameraSource.esp32,
        message: 'Cannot reach ESP32 at ${_settings.esp32Ip}',
      );
      return;
    }

    _updateConnection(
      status: ConnectionStatus.connected,
      source: CameraSource.esp32,
      message: 'Connected to ESP32-CAM',
    );

    _pollTimer = Timer.periodic(
      Duration(milliseconds: _settings.frameIntervalMs),
      (_) => _fetchEsp32Frame(),
    );
    _buttonPollTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.buttonPollIntervalMs),
      (_) => _fetchEsp32ButtonEvents(),
    );
    await _fetchEsp32Frame();
    await _fetchEsp32ButtonEvents();
  }

  Future<void> _fetchEsp32Frame() async {
    if (_connection.status != ConnectionStatus.connected) return;

    final start = DateTime.now();
    try {
      final response = await http
          .get(Uri.parse(_settings.captureUrl))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final latency = DateTime.now().difference(start).inMilliseconds;
        _emitFrame(response.bodyBytes, latencyMs: latency);
      }
    } catch (_) {
      _updateConnection(
        status: ConnectionStatus.error,
        source: CameraSource.esp32,
        message: 'Lost connection to ESP32',
      );
      stopPolling();
    }
  }

  void _emitFrame(Uint8List bytes, {int? latencyMs}) {
    _latestFrame = bytes;
    _connection = _connection.copyWith(
      lastFrameTime: DateTime.now(),
      framesReceived: _connection.framesReceived + 1,
      latencyMs: latencyMs,
    );
    _frameController.add(bytes);
    _connectionController.add(_connection);
  }

  void _updateConnection({
    ConnectionStatus? status,
    CameraSource? source,
    String? message,
  }) {
    _connection = _connection.copyWith(
      status: status,
      source: source ?? _connection.source,
      message: message,
    );
    _connectionController.add(_connection);
  }

  Future<void> _fetchEsp32ButtonEvents() async {
    if (_connection.status != ConnectionStatus.connected ||
        _connection.source != CameraSource.esp32) {
      return;
    }

    try {
      final response = await http
          .get(Uri.parse(_settings.eventsUrl))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final events = body['events'] as List<dynamic>? ?? [];
      for (final event in events) {
        final action = (event as Map<String, dynamic>)['action'] as String?;
        if (action != null && action.isNotEmpty) {
          _buttonEventController.add(action);
        }
      }
    } catch (_) {}
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _buttonPollTimer?.cancel();
    _buttonPollTimer = null;
  }

  Future<void> disconnect() async {
    stopPolling();
    if (_phoneController != null) {
      try {
        await _phoneController!.dispose();
      } catch (_) {}
      _phoneController = null;
    }
    _latestFrame = null;
    _connection = const CameraConnectionInfo();
    _connectionController.add(_connection);
  }

  void dispose() {
    disconnect();
    _frameController.close();
    _connectionController.close();
    _buttonEventController.close();
  }
}
