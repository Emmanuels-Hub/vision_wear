import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/connection_state.dart';

class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key, required this.connection});

  final CameraConnectionInfo connection;

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = _statusInfo();
    final detail = _detail();

    return Semantics(
      label: 'Connection status: $text',
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (connection.isBusy)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _detail() {
    if (!connection.isConnected) {
      return connection.deviceIp;
    }

    final parts = <String>[];
    if (connection.deviceIp != null) parts.add(connection.deviceIp!);
    if (connection.fps > 0) {
      parts.add('${connection.fps.toStringAsFixed(0)} fps');
    }
    if (connection.transport == FrameTransport.mjpegStream) {
      parts.add('stream');
    } else if (connection.transport == FrameTransport.pollCapture) {
      parts.add('polling');
    }
    if (connection.latencyMs != null) parts.add('${connection.latencyMs}ms');

    return parts.isEmpty ? null : parts.join(' · ');
  }

  (Color, IconData, String) _statusInfo() {
    switch (connection.status) {
      case ConnectionStatus.connected:
        final source = connection.source == CameraSource.esp32
            ? 'ESP32-CAM'
            : 'Phone camera';
        return (AppTheme.accent, Icons.wifi, 'Connected · $source');
      case ConnectionStatus.discovering:
        return (AppTheme.warning, Icons.search, 'Finding camera...');
      case ConnectionStatus.connecting:
        return (AppTheme.warning, Icons.sync, 'Connecting...');
      case ConnectionStatus.reconnecting:
        return (
          AppTheme.warning,
          Icons.wifi_tethering,
          connection.reconnectAttempts > 0
              ? 'Reconnecting (attempt ${connection.reconnectAttempts})'
              : 'Reconnecting...',
        );
      case ConnectionStatus.error:
        return (AppTheme.danger, Icons.wifi_off, connection.message);
      case ConnectionStatus.disconnected:
        return (Colors.grey, Icons.link_off, 'Not connected');
    }
  }
}
