enum CameraSource { esp32, phone, none }

enum ConnectionStatus { disconnected, connecting, connected, error }

class CameraConnectionInfo {
  const CameraConnectionInfo({
    this.status = ConnectionStatus.disconnected,
    this.source = CameraSource.none,
    this.message = 'Not connected',
    this.lastFrameTime,
    this.framesReceived = 0,
    this.latencyMs,
  });

  final ConnectionStatus status;
  final CameraSource source;
  final String message;
  final DateTime? lastFrameTime;
  final int framesReceived;
  final int? latencyMs;

  bool get isConnected => status == ConnectionStatus.connected;

  CameraConnectionInfo copyWith({
    ConnectionStatus? status,
    CameraSource? source,
    String? message,
    DateTime? lastFrameTime,
    int? framesReceived,
    int? latencyMs,
  }) {
    return CameraConnectionInfo(
      status: status ?? this.status,
      source: source ?? this.source,
      message: message ?? this.message,
      lastFrameTime: lastFrameTime ?? this.lastFrameTime,
      framesReceived: framesReceived ?? this.framesReceived,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}
