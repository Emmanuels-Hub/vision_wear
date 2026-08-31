import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the platform can tell us about the phone's current routing.
class NetworkRouting {
  const NetworkRouting({
    this.hasWifi = false,
    this.wifiIsDefault = false,
    this.activeIsCellular = false,
    this.wifiHasInternet = false,
    this.supported = false,
  });

  /// The phone is associated with a WiFi network.
  final bool hasWifi;

  /// That WiFi network is the one Android routes traffic over by default.
  final bool wifiIsDefault;

  /// Traffic is currently going out of the mobile interface.
  final bool activeIsCellular;

  /// The WiFi network has a working internet connection. False is normal and
  /// expected on the camera's own access point.
  final bool wifiHasInternet;

  /// False on platforms with no implementation (iOS, desktop, tests).
  final bool supported;

  /// The specific failure this whole service exists to catch: joined to WiFi,
  /// but Android is sending packets out of the cellular interface because the
  /// WiFi has no internet behind it.
  bool get isRoutingAwayFromWifi => hasWifi && !wifiIsDefault;
}

/// Pins the app's sockets to WiFi so requests to the camera actually reach it.
///
/// See `MainActivity.kt` for the full explanation. In short: Android will not
/// route traffic over a WiFi network that has no internet, and the ESP32-CAM's
/// access point has none. Without binding, every request to the camera is sent
/// over mobile data and times out.
class NetworkBindingService {
  static const MethodChannel _channel = MethodChannel('vision_wear/network');

  bool _bound = false;
  bool get isBound => _bound;

  /// Only Android needs this. iOS routes to the local subnet correctly once
  /// local-network permission is granted.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Pins this process to WiFi. Safe to call repeatedly.
  ///
  /// While bound the app cannot reach the internet, so this is only held while
  /// the ESP32 camera is in use.
  Future<bool> bindToWifi() async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('bindToWifi') ?? false;
      _bound = ok;
      if (ok) debugPrint('[Network] bound process to WiFi');
      return ok;
    } on PlatformException catch (e) {
      debugPrint('[Network] bind failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Releases the binding and lets the OS route normally again.
  Future<void> unbind() async {
    if (!isSupported || !_bound) return;
    try {
      await _channel.invokeMethod<bool>('unbind');
      _bound = false;
      debugPrint('[Network] released WiFi binding');
    } on PlatformException catch (e) {
      debugPrint('[Network] unbind failed: ${e.message}');
    } on MissingPluginException {
      _bound = false;
    }
  }

  /// Stops WiFi power saving from dropping the camera's UDP discovery beacon.
  Future<void> acquireMulticastLock() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('acquireMulticastLock');
    } on PlatformException catch (e) {
      debugPrint('[Network] multicast lock unavailable: ${e.message}');
    } on MissingPluginException {
      debugPrint('[Network] multicast lock not implemented on this platform');
    }
  }

  Future<void> releaseMulticastLock() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('releaseMulticastLock');
    } on PlatformException catch (e) {
      debugPrint('[Network] could not release multicast lock: ${e.message}');
    } on MissingPluginException {
      // Nothing was ever acquired.
    }
  }

  /// Reads the phone's current routing, for the connection diagnostics.
  Future<NetworkRouting> status() async {
    if (!isSupported) return const NetworkRouting();
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('status');
      if (raw == null) return const NetworkRouting();
      return NetworkRouting(
        hasWifi: raw['hasWifi'] as bool? ?? false,
        wifiIsDefault: raw['wifiIsDefault'] as bool? ?? false,
        activeIsCellular: raw['activeIsCellular'] as bool? ?? false,
        wifiHasInternet: raw['wifiHasInternet'] as bool? ?? false,
        supported: true,
      );
    } on PlatformException catch (_) {
      return const NetworkRouting();
    } on MissingPluginException {
      return const NetworkRouting();
    }
  }
}
