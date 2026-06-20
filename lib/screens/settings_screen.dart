import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/vision_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, VisionProvider>(
      builder: (context, settingsProvider, vision, _) {
        final settings = settingsProvider.settings;

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SectionHeader(title: 'Speech'),
                _SliderTile(
                  label: 'Speech rate',
                  value: settings.speechRate,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  displayValue: '${(settings.speechRate * 100).toInt()}%',
                  onChanged: (v) async {
                    await settingsProvider.setSpeechRate(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 16),
                _SectionHeader(title: 'Detection'),
                _SliderTile(
                  label: 'Confidence threshold',
                  value: settings.detectionConfidence,
                  min: 0.3,
                  max: 0.9,
                  divisions: 6,
                  displayValue:
                      '${(settings.detectionConfidence * 100).toInt()}%',
                  onChanged: (v) async {
                    await settingsProvider.setDetectionConfidence(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 8),
                _SliderTile(
                  label: 'Frame interval',
                  value: settings.frameIntervalMs.toDouble(),
                  min: 300,
                  max: 1500,
                  divisions: 12,
                  displayValue: '${settings.frameIntervalMs}ms',
                  onChanged: (v) async {
                    await settingsProvider.setFrameInterval(v.round());
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                SwitchListTile(
                  title: const Text('Announce all objects'),
                  subtitle: const Text(
                    'Off: only hazards and nearby obstacles',
                  ),
                  value: settings.announceAllObjects,
                  activeThumbColor: AppTheme.accent,
                  onChanged: (v) async {
                    await settingsProvider.setAnnounceAllObjects(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 16),
                _SectionHeader(title: 'Accessibility'),
                SwitchListTile(
                  title: const Text('Haptic feedback'),
                  subtitle: const Text('Vibrate on critical obstacles'),
                  value: settings.enableHaptics,
                  activeThumbColor: AppTheme.accent,
                  onChanged: (v) async {
                    await settingsProvider.setEnableHaptics(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                SwitchListTile(
                  title: const Text('Voice commands'),
                  subtitle: const Text('Control app with your voice'),
                  value: settings.enableVoiceCommands,
                  activeThumbColor: AppTheme.accent,
                  onChanged: (v) async {
                    await settingsProvider.setEnableVoiceCommands(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 16),
                _SectionHeader(title: 'Camera'),
                SwitchListTile(
                  title: const Text('Use phone camera'),
                  subtitle: const Text('Fallback when ESP32 is unavailable'),
                  value: settings.usePhoneCamera,
                  activeThumbColor: AppTheme.accent,
                  onChanged: (v) async {
                    await settingsProvider.setUsePhoneCamera(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Vision Wear v1.0.0\n'
                          'AI-powered navigation assistant for visually impaired users.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.accent,
            ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Text(
              displayValue,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppTheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
