import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/standby_platform.dart';
import '../widgets/clock/digital_clock.dart';
import 'deck/deck_view.dart';
import 'standby_clock.dart';
import 'standby_settings.dart';

/// Standby on/off, the clock's look with a live preview, and "Show now".
class StandbySettingsScreen extends StatefulWidget {
  const StandbySettingsScreen({super.key});

  @override
  State<StandbySettingsScreen> createState() => _StandbySettingsScreenState();
}

class _StandbySettingsScreenState extends State<StandbySettingsScreen> with WidgetsBindingObserver {
  late final StandbyPlatform _platform = context.read<StandbyPlatform>();
  bool? _enabled;
  bool? _keepOn;
  bool? _onRest;
  bool _canOpen = true;
  bool _mediaAccess = true;
  bool _audioPermission = true;

  /// The alarm in the small preview: a fixed sample.
  static final _sample = StandbyStatus(nextAlarm: DateTime.now().add(const Duration(hours: 8)));

  @override
  void initState() {
    super.initState();
    _platform.isEnabled().then((on) {
      if (mounted) setState(() => _enabled = on);
    });
    _platform.isKeepOn().then((on) {
      if (mounted) setState(() => _keepOn = on);
    });
    _platform.isOnRest().then((on) {
      if (mounted) setState(() => _onRest = on);
    });
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android's settings: it may have been allowed there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    final can = await _platform.canOpenFromLock();
    final media = await _platform.hasMediaAccess();
    final audio = await _platform.hasAudioPermission();
    if (mounted) {
      setState(() {
        _canOpen = can;
        _mediaAccess = media;
        _audioPermission = audio;
      });
    }
  }

  Future<void> _setEnabled(bool on) async {
    setState(() => _enabled = on);
    await _platform.setEnabled(on);
  }

  Future<void> _setKeepOn(bool on) async {
    setState(() => _keepOn = on);
    await _platform.setKeepOn(on);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<StandbyController>();
    final s = controller.settings;
    final glowStyle = s.style == StandbyStyle.glow;

    return Scaffold(
      appBar: AppBar(title: const Text('Standby clock')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.screen_lock_landscape_outlined),
            title: const Text('Standby'),
            subtitle: const Text('After you lock the phone, turn it on its side to show the clock'),
            value: _enabled ?? false,
            onChanged: _enabled == null ? null : _setEnabled,
          ),
          if (_enabled == true && !_canOpen)
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
              title: const Text('Allow it on the lock screen'),
              subtitle: const Text(
                'Turn on notifications and full-screen notifications for Minimal Launcher, so Android lets '
                'the clock open over the lock screen',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: _platform.openPermission,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.table_restaurant_outlined),
            title: const Text('Show when resting'),
            subtitle: const Text(
              'Lock the phone while it lies still on a table or stand, any way up, and the clock comes up. '
              'Not in a hand or pocket.',
            ),
            value: _onRest ?? true,
            onChanged: _onRest == null || _enabled != true
                ? null
                : (on) {
                    setState(() => _onRest = on);
                    _platform.setOnRest(on);
                  },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.light_mode_outlined),
            title: const Text('Keep screen on'),
            subtitle: Text(
              _keepOn ?? true
                  ? 'The clock stays until you turn the phone upright, tap, or press power'
                  : 'Stays on while charging; on battery the screen times out as usual',
            ),
            value: _keepOn ?? true,
            onChanged: _keepOn == null || _enabled != true ? null : _setKeepOn,
          ),
          const _Heading('Style'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<StandbyStyle>(
              segments: const [
                ButtonSegment(value: StandbyStyle.glow, icon: Icon(Icons.blur_on_rounded), label: Text('Glow')),
                ButtonSegment(value: StandbyStyle.deck, icon: Icon(Icons.album_outlined), label: Text('Deck')),
              ],
              selected: {s.style},
              onSelectionChanged: (v) => controller.update(s.copyWith(style: v.first)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              glowStyle
                  ? 'A big gradient clock with a soft glow and a glass now-playing tile'
                  : 'A vintage hi-fi deck: VU meters, a 7-segment clock, a spinning record and a 10-band EQ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 20 / 9,
                child: FittedBox(
                  child: SizedBox(
                    width: 880,
                    height: 396,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: glowStyle
                          ? StandbyClock(settings: s, status: _sample)
                          : DeckView(settings: s, status: _sample, now: DateTime.now()),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: FilledButton.icon(
              icon: const Icon(Icons.fullscreen_rounded),
              label: const Text('Show now'),
              onPressed: _platform.showNow,
            ),
          ),
          const ListTile(
            leading: Icon(Icons.battery_saver_outlined),
            subtitle: Text(
              'Lock the phone and lay it on its side within 30 seconds, or wake it sideways. It won\'t '
              'light up in a pocket, and closes if covered. Nothing runs the rest of the time.',
            ),
          ),

          if (glowStyle) ...[
            const _Heading('Font'),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in ClockFont.values)
                    _FontChoice(
                      font: f,
                      weight: s.weight.clamp(f.minWeight, f.maxWeight),
                      selected: f == s.font,
                      onTap: () => controller.update(s.copyWith(font: f)),
                    ),
                ],
              ),
            ),
            const _Heading('Weight'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Slider(
                min: s.font.minWeight.toDouble(),
                max: s.font.maxWeight.toDouble(),
                divisions: (s.font.maxWeight - s.font.minWeight) ~/ 50,
                value: s.fontWeight.toDouble(),
                label: '${s.fontWeight}',
                onChanged: (v) => controller.update(s.copyWith(weight: v.round())),
              ),
            ),
          ],

          if (glowStyle) ...[
            const _Heading('Colour'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (name, colors) in standbyAccents)
                    _Swatch(
                      name: name,
                      colors: colors,
                      selected: name == s.accent,
                      onTap: () => controller.update(s.copyWith(accent: name)),
                    ),
                ],
              ),
            ),
          ],

          const _Heading('Details'),
          SwitchListTile(
            secondary: const Icon(Icons.timer_outlined),
            title: const Text('Seconds'),
            subtitle: const Text('Small, beside the minutes'),
            value: s.seconds,
            onChanged: (v) => controller.update(s.copyWith(seconds: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.alarm_rounded),
            title: const Text('Next alarm'),
            subtitle: const Text('Under the time, when one is set'),
            value: s.alarm,
            onChanged: (v) => controller.update(s.copyWith(alarm: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined),
            title: const Text('Night mode'),
            subtitle: const Text('Dim and red from 10 PM to 6 AM, easy on eyes in a dark room'),
            value: s.nightMode,
            onChanged: (v) => controller.update(s.copyWith(nightMode: v)),
          ),
          if (glowStyle)
            SwitchListTile(
              secondary: const Icon(Icons.blur_on_rounded),
              title: const Text('Background glow'),
              subtitle: Text(
                s.glow
                    ? 'A soft gradient glow fills the screen behind the time'
                    : 'Off: black screen, the gradient on the clock digits only',
              ),
              value: s.glow,
              onChanged: (v) => controller.update(s.copyWith(glow: v)),
            ),
          const _Heading('Now playing'),
          SwitchListTile(
            secondary: const Icon(Icons.music_note_outlined),
            title: const Text('Show what\'s playing'),
            subtitle: Text(
              s.media
                  ? 'Music from any app, in a glass tile along the bottom, with play, pause and skip'
                  : 'Off: just the clock',
            ),
            value: s.media,
            onChanged: (v) {
              controller.update(s.copyWith(media: v));
              if (v && !_mediaAccess) _platform.openMediaAccess();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.palette_outlined),
            title: const Text('Match the song\'s colours'),
            subtitle: Text(
              glowStyle
                  ? 'While a song is shown, the clock takes the main colours of its cover'
                  : 'The clock, progress, record and glass controls take the colours of its cover',
            ),
            value: s.matchArt,
            onChanged: s.media ? (v) => controller.update(s.copyWith(matchArt: v)) : null,
          ),
          if (glowStyle)
            SwitchListTile(
              secondary: const Icon(Icons.image_outlined),
              title: const Text('Album art background'),
              subtitle: Text(
                s.artGlow
                    ? 'A dim, blurred copy of the song\'s cover fills the background'
                    : 'Hidden: the background stays black',
              ),
              value: s.artGlow,
              onChanged: s.media ? (v) => controller.update(s.copyWith(artGlow: v)) : null,
            ),
          if (glowStyle)
            SwitchListTile(
              secondary: const Icon(Icons.graphic_eq_rounded),
              title: const Text('Pulse with the beat'),
              subtitle: Text(
                s.glow
                    ? 'Patches of the glow flicker with the music: treble on the left, bass on the right'
                    : 'Needs the background glow, which is off',
              ),
              value: s.beatPulse && s.glow,
              onChanged: s.media && s.glow
                  ? (v) {
                      controller.update(s.copyWith(beatPulse: v));
                      if (v && !_audioPermission) _platform.requestAudioPermission();
                    }
                  : null,
            ),
          if (!glowStyle)
            ListTile(
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const Text('Live meters'),
              subtitle: Text(
                _audioPermission
                    ? 'The VU meters and the 10-band EQ move with what the phone plays'
                    : 'Allow the audio permission so the VU meters and EQ can move with the music',
              ),
              onTap: _audioPermission ? null : _platform.requestAudioPermission,
            ),
          if (s.media && !_audioPermission && (glowStyle ? s.glow && s.beatPulse : true))
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
              title: const Text('Allow the audio permission'),
              subtitle: const Text(
                'Android calls it "Microphone", but only the levels of the phone\'s own sound are read. The '
                'microphone is never used, and nothing is recorded or kept.',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: _platform.requestAudioPermission,
            ),
          if (s.media && !_mediaAccess)
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
              title: const Text('Allow notification access'),
              subtitle: const Text(
                'Android only lets apps with notification access see what\'s playing. Turn it on for '
                '"Standby now playing"; notifications themselves aren\'t read.',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: _platform.openMediaAccess,
            ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _FontChoice extends StatelessWidget {
  const _FontChoice({required this.font, required this.weight, required this.selected, required this.onTap});

  final ClockFont font;
  final int weight;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 96,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '10:42',
                  style: TextStyle(
                    fontFamily: font.family,
                    fontSize: 30,
                    fontVariations: [FontVariation('wght', weight.toDouble())],
                    height: 1,
                    color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(font.label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.colors, required this.selected, required this.onTap});

  final String name;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: name,
      child: Semantics(
        label: name,
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? ring : Colors.transparent, width: 2),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: colors.length >= 2 ? colors : [colors.first, colors.first],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
