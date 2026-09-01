import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/layout.dart';
import '../core/theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/vision_provider.dart';
import '../services/speech_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, VisionProvider>(
      builder: (context, settingsProvider, vision, _) {
        final settings = settingsProvider.settings;

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: AppPageBody(
            padding: EdgeInsets.zero,
            child: ListView(
              padding: context.pagePadding,
              children: [
                _SectionHeader(title: 'Appearance'),
                _ThemeModeTile(
                  value: settings.themeMode,
                  onChanged: settingsProvider.setThemeMode,
                ),
                const SizedBox(height: 8),
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
                _SliderTile(
                  label: 'Pitch',
                  value: settings.speechPitch,
                  min: 0.6,
                  max: 1.6,
                  divisions: 10,
                  displayValue: settings.speechPitch.toStringAsFixed(1),
                  onChanged: (v) async {
                    await settingsProvider.setSpeechPitch(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 8),
                _VoicePicker(
                  voices: vision.availableVoices,
                  selectedName: settings.voiceName,
                  onSelected: (voice) async {
                    await settingsProvider.setVoice(
                      voice?.name ?? '',
                      voice?.locale ?? '',
                    );
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 16),
                _SectionHeader(title: 'Alerts'),
                _SliderTile(
                  label: 'Minimum gap between alerts',
                  value: settings.summarizeIntervalMs.toDouble(),
                  min: 4000,
                  max: 15000,
                  divisions: 11,
                  displayValue:
                      '${(settings.summarizeIntervalMs / 1000).toStringAsFixed(0)}s',
                  onChanged: (v) async {
                    await settingsProvider.setSummarizeInterval(v.round());
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                SwitchListTile(
                  title: const Text('Only what is in your path'),
                  subtitle: const Text(
                    'Ignores objects off to the far left and right',
                  ),
                  value: settings.announceOnlyCenter,
                  onChanged: (v) async {
                    await settingsProvider.setAnnounceOnlyCenter(v);
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
                  onChanged: (v) async {
                    await settingsProvider.setAnnounceAllObjects(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                const SizedBox(height: 16),
                _SectionHeader(title: 'Accessibility'),
                SwitchListTile(
                  title: const Text('Haptic feedback'),
                  subtitle: const Text(
                    'A short tap to confirm your own actions. Detections never '
                    'vibrate.',
                  ),
                  value: settings.enableHaptics,
                  onChanged: (v) async {
                    await settingsProvider.setEnableHaptics(v);
                    vision.updateSettings(settingsProvider.settings);
                  },
                ),
                SwitchListTile(
                  title: const Text('Voice commands'),
                  subtitle: const Text('Control app with your voice'),
                  value: settings.enableVoiceCommands,
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

/// Light / dark / system selector.
///
/// A segmented control rather than a dropdown, so every option is its own
/// large, permanently-visible tap target instead of being hidden behind an
/// extra interaction.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, 'System', Icons.brightness_auto),
      (ThemeMode.light, 'Light', Icons.light_mode),
      (ThemeMode.dark, 'Dark', Icons.dark_mode),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: context.texts.bodyLarge),
          const SizedBox(height: 4),
          Text(
            "System follows your phone's light or dark setting.",
            style: context.texts.bodySmall?.copyWith(
              color: context.appColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: [
              for (final (mode, label, icon) in options)
                ButtonSegment<ThemeMode>(
                  value: mode,
                  label: Text(label),
                  icon: Icon(icon),
                  tooltip: '$label theme',
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
            style: ButtonStyle(
              // The global 64px ElevatedButton height is too tall here, but
              // each segment still clears the 48dp accessibility minimum.
              minimumSize: WidgetStateProperty.all(const Size(0, 52)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the user pick the TTS voice by ear.
///
/// The default engine voice is the flat, robotic one; the good voices are
/// installed but never selected unless something asks for them by name. "Best
/// available" is the automatic choice made by [SpeechService].
class _VoicePicker extends StatelessWidget {
  const _VoicePicker({
    required this.voices,
    required this.selectedName,
    required this.onSelected,
  });

  final List<SpeechVoice> voices;
  final String selectedName;
  final ValueChanged<SpeechVoice?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (voices.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Voice'),
        subtitle: Text(
          'No alternative voices installed. Add more in your '
          "phone's text-to-speech settings.",
          style: TextStyle(color: context.appColors.muted),
        ),
      );
    }

    // Cap the list: some Android engines report over a hundred voices, which
    // is unusable. They are sorted best-first, so the top of the list is the
    // part worth showing.
    final shown = voices.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Voice', style: context.texts.bodyLarge),
        const SizedBox(height: 4),
        Text(
          'Tap to hear a sample.',
          style: context.texts.bodySmall?.copyWith(
            color: context.appColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: selectedName,
          onChanged: (name) {
            if (name == null || name.isEmpty) {
              onSelected(null);
              return;
            }
            onSelected(voices.firstWhere((v) => v.name == name));
          },
          child: Column(
            children: [
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: '',
                title: const Text('Best available'),
                subtitle: Text(
                  'Picks the clearest installed voice automatically',
                  style: TextStyle(color: context.appColors.muted),
                ),
                activeColor: context.appColors.accent,
              ),
              for (final voice in shown)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: voice.name,
                  title: Text(voice.displayName),
                  subtitle: Text(
                    voice.locale,
                    style: TextStyle(color: context.appColors.muted),
                  ),
                  activeColor: context.appColors.accent,
                  secondary: IconButton(
                    icon: const Icon(Icons.volume_up),
                    tooltip: 'Preview ${voice.displayName}',
                    onPressed: () =>
                        context.read<VisionProvider>().previewVoice(voice),
                  ),
                ),
            ],
          ),
        ),
      ],
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
              color: context.appColors.brand,
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
                color: context.appColors.muted,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: context.colors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
