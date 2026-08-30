import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';

/// A Vision Wear device found on the network.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.ip,
    this.controlPort = AppConstants.controlPort,
    this.streamPort = AppConstants.streamPort,
    this.eventsPort = AppConstants.eventsPort,
    this.version,
    this.mode,
    this.cameraReady = true,
    this.viaBeacon = false,
  });

  final String ip;
  final int controlPort;
  final int streamPort;
  final int eventsPort;
  final String? version;
  final String? mode;
  final bool cameraReady;

  /// True when the device announced itself, false when we found it by probing.
  final bool viaBeacon;

  @override
  String toString() =>
      'DiscoveredDevice($ip:$controlPort, fw=$version, beacon=$viaBeacon)';
}

/// Finds the ESP32-CAM without the user typing an IP address.
///
/// Three strategies, cheapest first:
///   1. Listen for the firmware's UDP beacon. Works on the device's own AP and
///      on a shared home network / phone hotspot, and costs nothing.
///   2. Probe a short list of likely addresses (last known good, the AP
///      default, common gateway addresses).
///   3. Sweep the phone's own /24 subnet. Only reached when broadcast is
///      blocked, e.g. by AP client isolation on a home router.
class DeviceDiscoveryService {
  RawDatagramSocket? _beaconSocket;
  StreamSubscription<RawSocketEvent>? _beaconSub;

  final _deviceController = StreamController<DiscoveredDevice>.broadcast();

  /// Devices as they announce themselves. Emits continuously, so a device that
  /// changes address (AP -> home WiFi) is picked up without a rescan.
  Stream<DiscoveredDevice> get deviceStream => _deviceController.stream;

  DiscoveredDevice? _lastSeen;
  DiscoveredDevice? get lastSeen => _lastSeen;

  bool get isListening => _beaconSocket != null;

  /// Starts the passive beacon listener. Safe to call repeatedly.
  Future<void> startBeaconListener() async {
    if (_beaconSocket != null) return;

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
      socket.broadcastEnabled = true;
      _beaconSocket = socket;

      _beaconSub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final device = _parseBeacon(datagram);
        if (device != null) {
          _lastSeen = device;
          if (!_deviceController.isClosed) _deviceController.add(device);
        }
      }, onError: (_) {});
    } catch (e) {
      // Port already bound by another app, or the platform refused it. The
      // active probes below still work, so this is not fatal.
      debugPrint('Discovery: beacon listener unavailable ($e)');
    }
  }

  Future<void> stopBeaconListener() async {
    await _beaconSub?.cancel();
    _beaconSub = null;
    _beaconSocket?.close();
    _beaconSocket = null;
  }

  DiscoveredDevice? _parseBeacon(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final map = jsonDecode(text) as Map<String, dynamic>;
      if (map['device'] != AppConstants.discoveryDeviceName) return null;

      // The beacon carries both addresses. Prefer whichever subnet this packet
      // actually arrived from, so we talk to the device over the interface we
      // can already reach it on.
      final apIp = (map['ap_ip'] as String?)?.trim() ?? '';
      final staIp = (map['sta_ip'] as String?)?.trim() ?? '';
      final senderIp = datagram.address.address;

      String chosen = senderIp;
      if (staIp.isNotEmpty && _sameSubnet(staIp, senderIp)) {
        chosen = staIp;
      } else if (apIp.isNotEmpty && _sameSubnet(apIp, senderIp)) {
        chosen = apIp;
      }

      return DiscoveredDevice(
        ip: chosen,
        controlPort: (map['control_port'] as num?)?.toInt() ??
            AppConstants.controlPort,
        streamPort:
            (map['stream_port'] as num?)?.toInt() ?? AppConstants.streamPort,
        eventsPort:
            (map['events_port'] as num?)?.toInt() ?? AppConstants.eventsPort,
        version: map['version'] as String?,
        mode: map['mode'] as String?,
        cameraReady: map['camera_ready'] as bool? ?? true,
        viaBeacon: true,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _sameSubnet(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    if (pa.length != 4 || pb.length != 4) return false;
    return pa[0] == pb[0] && pa[1] == pb[1] && pa[2] == pb[2];
  }

  /// Waits up to [timeout] for a beacon. Returns immediately if one has
  /// already arrived.
  Future<DiscoveredDevice?> awaitBeacon({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    await startBeaconListener();
    if (_lastSeen != null) return _lastSeen;
    try {
      return await deviceStream.first.timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Full discovery sweep. [preferredIp] is tried first so a working setup
  /// reconnects in one round trip.
  Future<DiscoveredDevice?> discover({
    String? preferredIp,
    Duration beaconWait = const Duration(milliseconds: 1800),
    bool allowSubnetScan = true,
  }) async {
    // 1. Last known good address. Cheapest possible path and the common case.
    if (preferredIp != null && preferredIp.isNotEmpty) {
      if (await _probe(preferredIp)) {
        return DiscoveredDevice(ip: preferredIp);
      }
    }

    // 2. Beacon.
    final beacon = await awaitBeacon(timeout: beaconWait);
    if (beacon != null && await _probe(beacon.ip, port: beacon.controlPort)) {
      return beacon;
    }

    // 3. Likely fixed addresses.
    for (final candidate in await _candidateAddresses()) {
      if (candidate == preferredIp) continue;
      if (await _probe(candidate)) {
        return DiscoveredDevice(ip: candidate);
      }
    }

    // 4. Subnet sweep, last resort.
    if (allowSubnetScan) {
      final found = await _scanLocalSubnets();
      if (found != null) return DiscoveredDevice(ip: found);
    }

    return null;
  }

  /// Cheap liveness probe. Uses /health, which the firmware answers without
  /// touching the camera, so a busy or wedged sensor does not read as "offline".
  Future<bool> _probe(
    String ip, {
    int port = AppConstants.controlPort,
    Duration? timeout,
  }) async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse('http://$ip:$port${AppConstants.defaultHealthPath}'))
          .timeout(
            timeout ??
                const Duration(milliseconds: AppConstants.healthTimeoutMs),
          );
      return response.statusCode == 200;
    } catch (_) {
      // Older firmware has no /health. Fall back to /status before giving up.
      try {
        final response = await client
            .get(Uri.parse('http://$ip:$port${AppConstants.defaultStatusPath}'))
            .timeout(
              timeout ??
                  const Duration(milliseconds: AppConstants.healthTimeoutMs),
            );
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    } finally {
      client.close();
    }
  }

  Future<List<String>> _candidateAddresses() async {
    final candidates = <String>{AppConstants.defaultEsp32Ip};

    // When the phone is on the device's AP, the phone gets 192.168.4.x and the
    // device is the gateway at .1. On a home network the device is a normal
    // client, so .1 is the router instead and the sweep below handles it.
    for (final prefix in await _localSubnetPrefixes()) {
      candidates.add('$prefix.1');
    }

    return candidates.toList();
  }

  Future<List<String>> _localSubnetPrefixes() async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (_) {}
    return prefixes.toList();
  }

  /// Sweeps every /24 the phone has an address on. Runs in bounded batches so
  /// we do not open 254 sockets at once, which Android will throttle.
  Future<String?> _scanLocalSubnets() async {
    const batchSize = 32;
    const probeTimeout = Duration(milliseconds: 400);

    for (final prefix in await _localSubnetPrefixes()) {
      for (var start = 1; start <= 254; start += batchSize) {
        final end = (start + batchSize - 1).clamp(1, 254);
        final futures = <Future<String?>>[];

        for (var host = start; host <= end; host++) {
          final ip = '$prefix.$host';
          futures.add(
            _probe(ip, timeout: probeTimeout).then((ok) => ok ? ip : null),
          );
        }

        final results = await Future.wait(futures);
        final hit = results.firstWhere((r) => r != null, orElse: () => null);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  void dispose() {
    stopBeaconListener();
    _deviceController.close();
  }
}
