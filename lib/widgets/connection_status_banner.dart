import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/connection_state.dart';

class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key, required this.connection});

  final CameraConnectionInfo connection;

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = _statusInfo();

    return Semantics(
      label: 'Connection status: $text',
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
                  if (connection.isConnected && connection.latencyMs != null)
                    Text(
                      '${connection.framesReceived} frames · ${connection.latencyMs}ms',
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

  (Color, IconData, String) _statusInfo() {
    switch (connection.status) {
      case ConnectionStatus.connected:
        final source = connection.source == CameraSource.esp32
            ? 'ESP32-CAM'
            : 'Phone camera';
        return (AppTheme.accent, Icons.wifi, 'Connected · $source');
      case ConnectionStatus.connecting:
        return (AppTheme.warning, Icons.sync, 'Connecting...');
      case ConnectionStatus.error:
        return (AppTheme.danger, Icons.wifi_off, connection.message);
      case ConnectionStatus.disconnected:
        return (Colors.grey, Icons.link_off, 'Not connected');
    }
  }
}
