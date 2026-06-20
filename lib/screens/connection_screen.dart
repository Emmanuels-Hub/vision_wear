import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/vision_provider.dart';
import '../widgets/connection_status_banner.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final TextEditingController _ipController;
  late final TextEditingController _pathController;
  bool _usePhoneCamera = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _ipController = TextEditingController(text: settings.esp32Ip);
    _pathController = TextEditingController(text: settings.capturePath);
    _usePhoneCamera = settings.usePhoneCamera;
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final settingsProvider = context.read<SettingsProvider>();
    final vision = context.read<VisionProvider>();

    await settingsProvider.update(
      settingsProvider.settings.copyWith(
        esp32Ip: _ipController.text.trim(),
        capturePath: _pathController.text.trim(),
        usePhoneCamera: _usePhoneCamera,
      ),
    );

    vision.updateSettings(settingsProvider.settings);
    await vision.disconnectCamera();
    await vision.connectCamera();
  }

  Future<void> _testConnection() async {
    final vision = context.read<VisionProvider>();
    await vision.testConnection(
      _ipController.text.trim(),
      _pathController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionProvider>(
      builder: (context, vision, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Camera Connection')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConnectionStatusBanner(connection: vision.connection),
                  const SizedBox(height: 24),
                  Text(
                    'Connect to ESP32-CAM',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the IP address of your ESP32-CAM module. '
                    'Default AP mode IP is usually 192.168.4.1',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white60,
                        ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('Use phone camera instead'),
                    subtitle: const Text(
                      'For testing without ESP32 hardware',
                    ),
                    value: _usePhoneCamera,
                    activeThumbColor: AppTheme.accent,
                    onChanged: (v) => setState(() => _usePhoneCamera = v),
                  ),
                  if (!_usePhoneCamera) ...[
                    TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'ESP32 IP Address',
                        hintText: '192.168.4.1',
                        prefixIcon: Icon(Icons.router),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        labelText: 'Capture endpoint',
                        hintText: '/capture',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _testConnection,
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('Test Connection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cardDark,
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _saveAndConnect,
                    icon: const Icon(Icons.link),
                    label: const Text('Save & Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (vision.connection.isConnected)
                    OutlinedButton.icon(
                      onPressed: vision.disconnectCamera,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        minimumSize: const Size(double.infinity, 56),
                      ),
                    ),
                  const SizedBox(height: 32),
                  _SetupGuide(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SetupGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const steps = [
      'Flash the ESP32-CAM firmware (see firmware/ folder)',
      'Power on the ESP32-CAM module',
      'Connect phone WiFi to the ESP32 network (VisionWear-CAM)',
      'Return to this app and tap Save & Connect',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  'Quick Setup',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...steps.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AppTheme.primary,
                          child: Text(
                            '${e.key + 1}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.value)),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
