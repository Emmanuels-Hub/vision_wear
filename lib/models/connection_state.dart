enum CameraSource { esp32, phone, none }

enum ConnectionStatus {
  disconnected,
  discovering,
  connecting,
  connected,
  reconnecting,
  error,
}

/// How frames are currently arriving from the ESP32.
///
/// [mjpegStream] is a single long-lived HTTP connection and is what we always
/// try first: it removes the per-frame TCP handshake entirely. [pollCapture]
/// is the fallback for networks or proxies that break long-lived responses.
enum FrameTransport { none, mjpegStream, pollCapture, phoneCamera }

class CameraConnectionInfo {
  const CameraConnectionInfo({
    this.status = ConnectionStatus.disconnected,
    this.source = CameraSource.none,
    this.transport = FrameTransport.none,
    this.message = 'Not connected',
    this.deviceIp,
    this.lastFrameTime,
    this.framesReceived = 0,
    this.latencyMs,
    this.fps = 0,
    this.reconnectAttempts = 0,
    this.deviceMode,
  });

  final ConnectionStatus status;
  final CameraSource source;
  final FrameTransport transport;
  final String message;
  final String? deviceIp;
  final DateTime? lastFrameTime;
  final int framesReceived;
  final int? latencyMs;
  final double fps;
  final int reconnectAttempts;

  /// Mode the device itself reports it is in, used to keep the phone UI in
  /// sync with the physical mode button.
  final String? deviceMode;

  bool get isConnected => status == ConnectionStatus.connected;

  /// True while the supervisor is actively working to restore the link. The UI
  /// should show a "reconnecting" affordance rather than a hard failure,
  /// because no user action is required.
  bool get isBusy =>
      status == ConnectionStatus.connecting ||
      status == ConnectionStatus.discovering ||
      status == ConnectionStatus.reconnecting;

  bool get hasLiveFrames => isConnected && transport != FrameTransport.none;

  CameraConnectionInfo copyWith({
    ConnectionStatus? status,
    CameraSource? source,
    FrameTransport? transport,
    String? message,
    String? deviceIp,
    DateTime? lastFrameTime,
    int? framesReceived,
    int? latencyMs,
    double? fps,
    int? reconnectAttempts,
    String? deviceMode,
  }) {
    return CameraConnectionInfo(
      status: status ?? this.status,
      source: source ?? this.source,
      transport: transport ?? this.transport,
      message: message ?? this.message,
      deviceIp: deviceIp ?? this.deviceIp,
      lastFrameTime: lastFrameTime ?? this.lastFrameTime,
      framesReceived: framesReceived ?? this.framesReceived,
      latencyMs: latencyMs ?? this.latencyMs,
      fps: fps ?? this.fps,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      deviceMode: deviceMode ?? this.deviceMode,
    );
  }
}
