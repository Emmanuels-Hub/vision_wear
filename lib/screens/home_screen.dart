import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_mode.dart';
import '../providers/settings_provider.dart';
import '../providers/vision_provider.dart';
import '../widgets/accessible_button.dart';
import '../widgets/connection_status_banner.dart';
import 'connection_screen.dart';
import 'help_screen.dart';
import 'settings_screen.dart';
import 'vision_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final vision = context.read<VisionProvider>();
      final settingsProvider = context.read<SettingsProvider>();

      // Settings load asynchronously at startup; connecting before they land
      // would use the default IP rather than the saved one.
      if (settingsProvider.isLoading) {
        await settingsProvider.load();
      }
      if (!mounted) return;

      vision.updateSettings(settingsProvider.settings);

      // Connect as soon as the app opens so the ESP32's physical buttons work
      // without the user first navigating into the vision screen. The service
      // supervises the link from here on and reconnects on its own.
      if (!vision.connection.isConnected && !vision.connection.isBusy) {
        await vision.connectCamera();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<VisionProvider, SettingsProvider>(
      builder: (context, vision, settings, _) {
        _handleNavigationHint(vision.statusMessage);

        return Scaffold(
          appBar: AppBar(
            title: const Text(AppConstants.appName),
            actions: [
              Semantics(
                label: 'Voice command',
                button: true,
                child: IconButton(
                  icon: Icon(
                    vision.isVoiceListening ? Icons.mic : Icons.mic_none,
                    color: vision.isVoiceListening
                        ? context.appColors.accent
                        : context.appColors.muted,
                  ),
                  onPressed: settings.settings.enableVoiceCommands
                      ? vision.toggleVoiceListening
                      : null,
                  tooltip: 'Voice commands',
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConnectionStatusBanner(connection: vision.connection),
                  const SizedBox(height: 24),
                  Text(
                    'How can I help you navigate?',
                    style: Theme.of(context).textTheme.headlineMedium,
                    semanticsLabel: 'How can I help you navigate?',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap a button or use voice commands',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: context.appColors.muted),
                  ),
                  const SizedBox(height: 28),
                  // Mode indicator. Tapping cycles the mode and pushes it to
                  // the device, mirroring the physical mode button so the two
                  // can never disagree.
                  Semantics(
                    button: true,
                    label:
                        'Current mode, ${vision.currentMode.displayName}. '
                        'Double tap to change mode.',
                    child: InkWell(
                      onTap: vision.cycleMode,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.appColors.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.appColors.accent, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Current Mode',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: context.appColors.muted),
                                  ),
                                ),
                                Icon(
                                  Icons.swap_horiz,
                                  size: 18,
                                  color: context.appColors.muted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              vision.currentMode.displayName,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Action: ${vision.currentMode.actionDescription}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: context.appColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: ListView(
                      children: [
                        AccessibleButton(
                          label: 'Start Vision',
                          subtitle: 'Detect obstacles and objects in real-time',
                          icon: Icons.visibility,
                          isPrimary: true,
                          semanticHint: 'Starts live vision assistance',
                          onPressed: () => _openVision(context),
                        ),
                        const SizedBox(height: 12),
                        AccessibleButton(
                          label: 'Camera Connection',
                          subtitle: vision.connection.isConnected
                              ? 'Connected'
                              : 'Set up ESP32-CAM',
                          icon: Icons.wifi_tethering,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ConnectionScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AccessibleButton(
                          label: 'Describe Scene',
                          subtitle: 'Hear what is around you now',
                          icon: Icons.record_voice_over,
                          onPressed: vision.describeScene,
                        ),
                        const SizedBox(height: 12),
                        AccessibleButton(
                          label: 'Scan Obstacles',
                          subtitle: 'Check for hazards on your path',
                          icon: Icons.warning_amber,
                          color: context.appColors.warning.withValues(alpha: 0.3),
                          onPressed: vision.scanObstacles,
                        ),
                        const SizedBox(height: 12),
                        AccessibleButton(
                          label: 'Settings',
                          subtitle: 'Speech, detection, and preferences',
                          icon: Icons.settings,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AccessibleButton(
                          label: 'Help & Setup',
                          subtitle: 'ESP32 guide and voice commands',
                          icon: Icons.help_outline,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HelpScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleNavigationHint(String status) {
    if (status.startsWith('navigate:')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = status.split(':').last;
        if (route == 'settings') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        } else if (route == 'help') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HelpScreen()),
          );
        }
      });
    }
  }

  void _openVision(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VisionScreen()),
    );
  }
}
