import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/layout.dart';
import '../core/theme/app_theme.dart';
import '../models/app_mode.dart';
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
  final _ssidController = TextEditingController();
  final _wifiPassController = TextEditingController();

  bool _usePhoneCamera = false;
  bool _autoDiscover = true;
  bool _busy = false;
  bool _showManualAddress = false;
  DeviceStatus? _deviceStatus;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _ipController = TextEditingController(text: settings.esp32Ip);
    _pathController = TextEditingController(text: settings.capturePath);
    _usePhoneCamera = settings.usePhoneCamera;
    _autoDiscover = settings.autoDiscover;

    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDeviceStatus());
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pathController.dispose();
    _ssidController.dispose();
    _wifiPassController.dispose();
    super.dispose();
  }

  Future<void> _refreshDeviceStatus() async {
    final vision = context.read<VisionProvider>();
    final status = await vision.fetchDeviceStatus();
    if (!mounted) return;
    setState(() => _deviceStatus = status);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.appColors.danger : context.colors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveAndConnect() async {
    setState(() => _busy = true);
    try {
      final settingsProvider = context.read<SettingsProvider>();
      final vision = context.read<VisionProvider>();

      await settingsProvider.update(
        settingsProvider.settings.copyWith(
          esp32Ip: _ipController.text.trim(),
          capturePath: _pathController.text.trim(),
          usePhoneCamera: _usePhoneCamera,
          autoDiscover: _autoDiscover,
        ),
      );

      vision.updateSettings(settingsProvider.settings);
      await vision.disconnectCamera();
      await vision.connectCamera();
      await _refreshDeviceStatus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _busy = true);
    try {
      final vision = context.read<VisionProvider>();
      await vision.testConnection(
        _ipController.text.trim(),
        _pathController.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareWifi() async {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      _toast('Enter the network name first', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final vision = context.read<VisionProvider>();
      final ok = await vision.provisionDeviceWifi(
        ssid,
        _wifiPassController.text,
      );

      if (ok) {
        _wifiPassController.clear();
        _toast('Sent to the camera. It will join "$ssid" in a few seconds.');
        // Give the board time to associate and pick up a lease.
        await Future.delayed(const Duration(seconds: 6));
        await _refreshDeviceStatus();
      } else {
        _toast(
          'Could not reach the camera. Connect to its WiFi first.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionProvider>(
      builder: (context, vision, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Camera Connection'),
            actions: [
              IconButton(
                onPressed: _busy ? null : _refreshDeviceStatus,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh device status',
              ),
            ],
          ),
          body: AppPageBody(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              padding: context.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConnectionStatusBanner(connection: vision.connection),
                  const SizedBox(height: 20),

                  if (_deviceStatus != null) ...[
                    _DeviceCard(status: _deviceStatus!),
                    const SizedBox(height: 20),
                  ],

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use phone camera instead'),
                    subtitle: const Text('For testing without ESP32 hardware'),
                    value: _usePhoneCamera,
                    onChanged: (v) => setState(() => _usePhoneCamera = v),
                  ),

                  if (!_usePhoneCamera) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Find the camera automatically'),
                      subtitle: const Text(
                        'Listens for the device instead of using a fixed IP',
                      ),
                      value: _autoDiscover,
                      onChanged: (v) => setState(() => _autoDiscover = v),
                    ),
                    const SizedBox(height: 8),

                    // The manual address is a fallback, so it stays collapsed
                    // unless auto-discovery is off or the user asks for it.
                    if (!_autoDiscover || _showManualAddress) ...[
                      TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'ESP32 IP address',
                          hintText: AppConstants.defaultEsp32Ip,
                          prefixIcon: Icon(Icons.router),
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pathController,
                        decoration: const InputDecoration(
                          labelText: 'Capture endpoint',
                          hintText: AppConstants.defaultCapturePath,
                          prefixIcon: Icon(Icons.link),
                        ),
                        autocorrect: false,
                      ),
                    ] else
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showManualAddress = true),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Enter an address manually'),
                      ),
                  ],

                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _testConnection,
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('Test Connection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.surfaceContainerHighest,
                      foregroundColor: context.colors.onSurface,
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _saveAndConnect,
                    icon: _busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colors.onPrimary,
                            ),
                          )
                        : const Icon(Icons.link),
                    label: const Text('Save & Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (vision.connection.isConnected)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : vision.disconnectCamera,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.appColors.danger,
                        minimumSize: const Size(double.infinity, 56),
                      ),
                    ),

                  if (!_usePhoneCamera) ...[
                    const SizedBox(height: 28),
                    _ShareWifiCard(
                      ssidController: _ssidController,
                      passwordController: _wifiPassController,
                      busy: _busy,
                      onSubmit: _shareWifi,
                      staConnected: _deviceStatus?.staConnected ?? false,
                      staSsid: _deviceStatus?.staSsid ?? '',
                    ),
                  ],

                  const SizedBox(height: 28),
                  const _SetupGuide(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory, color: context.appColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.device,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  'v${status.version}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(context, 'Mode', status.parsedMode?.displayName ?? status.currentMode),
            _row(context, 'Camera', status.cameraReady ? 'Ready' : 'Not ready'),
            _row(context, 'Access point', status.apIp.isEmpty ? '—' : status.apIp),
            _row(
              context,
              'Home network',
              status.staConnected
                  ? '${status.staSsid} · ${status.staIp}'
                  : 'Not joined',
            ),
            if (status.uptimeMs > 0)
              _row(context, 'Uptime', '${(status.uptimeMs / 60000).floor()} min'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: context.appColors.muted, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// Hands the board credentials for a normal WiFi network.
///
/// This is what lets the phone keep its internet connection: instead of the
/// phone joining the camera's access point (which has no upstream), the camera
/// joins the same network the phone is already on.
class _ShareWifiCard extends StatefulWidget {
  const _ShareWifiCard({
    required this.ssidController,
    required this.passwordController,
    required this.busy,
    required this.onSubmit,
    required this.staConnected,
    required this.staSsid,
  });

  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final bool busy;
  final VoidCallback onSubmit;
  final bool staConnected;
  final String staSsid;

  @override
  State<_ShareWifiCard> createState() => _ShareWifiCardState();
}

class _ShareWifiCardState extends State<_ShareWifiCard> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_password, color: context.appColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keep internet while connected',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.staConnected
                  ? 'The camera has joined "${widget.staSsid}". Your phone can '
                        'stay on that network and keep its internet connection.'
                  : 'The camera\'s own WiFi has no internet. Give it your '
                        'network name and password and it will join that '
                        'network instead, so your phone keeps internet while '
                        'still seeing the camera.',
              style: TextStyle(color: context.appColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.ssidController,
              decoration: const InputDecoration(
                labelText: 'Network name (SSID)',
                prefixIcon: Icon(Icons.wifi),
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.passwordController,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Network password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sent directly to the camera over its own WiFi and stored only on '
              'the device.',
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: widget.busy ? null : widget.onSubmit,
              icon: const Icon(Icons.send),
              label: const Text('Send to camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupGuide extends StatelessWidget {
  const _SetupGuide();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Flash the ESP32-CAM firmware (see the firmware/ folder)',
      'Power on the ESP32-CAM module',
      'Join the "${AppConstants.apSsid}" WiFi network (password: '
          '${AppConstants.apPassword})',
      'Return here — the app finds the camera on its own',
      'Optional: share your home WiFi above so your phone keeps internet',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: context.appColors.accent),
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
                      backgroundColor: context.colors.primary,
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
