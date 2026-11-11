import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

import 'protocol_session.dart';

/// One entry in the Live mode picker.
class LiveMode {
  const LiveMode({
    required this.type,
    required this.title,
    required this.summary,
    required this.icon,
    required this.group,
  });

  final TestType type;

  /// Short name shown on the mode button ("Free pull").
  final String title;

  /// One plain sentence: what you will be asked to do.
  final String summary;
  final IconData icon;
  final LiveModeGroup group;
}

enum LiveModeGroup {
  basics('Basics'),
  training('Training'),
  warmup('Warm-up');

  const LiveModeGroup(this.label);
  final String label;
}

String _pct(double f) => '${(f * 100).round()} %';

/// Every mode the Live screen offers, in picker order. The first three are
/// the everyday ones; the rest are tucked under "More modes".
final List<LiveMode> kLiveModes = [
  const LiveMode(
    type: TestType.custom,
    title: 'Free pull',
    summary: 'Press Start and pull however you like. Everything is recorded.',
    icon: Icons.show_chart,
    group: LiveModeGroup.basics,
  ),
  const LiveMode(
    type: TestType.peakForce,
    title: 'Max pull',
    summary:
        '3 s countdown, then one all-out pull for '
        '$kPeakPullMinSeconds–$kPeakPullMaxSeconds s.',
    icon: Icons.arrow_upward,
    group: LiveModeGroup.basics,
  ),
  LiveMode(
    type: TestType.repeaters,
    title: 'Repeaters 7:3',
    summary:
        '$kRepeaterReps × $kRepeaterWorkSeconds s on / '
        '$kRepeaterRestSeconds s off at ${_pct(kRepeaterLoadFraction)} '
        'of your max.',
    icon: Icons.repeat,
    group: LiveModeGroup.basics,
  ),
  const LiveMode(
    type: TestType.rfd,
    title: 'Explosive pull',
    summary: 'Pull as fast as you can. Measures how quickly you reach peak.',
    icon: Icons.bolt,
    group: LiveModeGroup.training,
  ),
  LiveMode(
    type: TestType.endurance,
    title: 'Endurance hold',
    summary:
        'Hold ${_pct(kEnduranceLoadFraction)} of your max until form breaks.',
    icon: Icons.timer_outlined,
    group: LiveModeGroup.training,
  ),
  const LiveMode(
    type: TestType.warmupTour,
    title: 'Warm-up tour',
    summary: 'Guided: curls, ramps and drags, one hand at a time.',
    icon: Icons.tour_outlined,
    group: LiveModeGroup.warmup,
  ),
  const LiveMode(
    type: TestType.followCurve,
    title: 'Follow the curve',
    summary: 'Trace the green target: ramp up, hold, slow release.',
    icon: Icons.timeline,
    group: LiveModeGroup.warmup,
  ),
  LiveMode(
    type: TestType.holdRelease,
    title: 'Hold & release',
    summary:
        'Hold $kHoldReleaseHoldSeconds s at '
        '${_pct(kHoldReleaseLoadFraction)}, then let go slowly.',
    icon: Icons.pan_tool_outlined,
    group: LiveModeGroup.warmup,
  ),
  LiveMode(
    type: TestType.warmupProgressive,
    title: 'Progressive ramp',
    summary:
        'Light pulls stepping from ${_pct(kWarmupProgressiveStartFraction)} '
        'to ${_pct(kWarmupProgressiveEndFraction)}.',
    icon: Icons.stairs_outlined,
    group: LiveModeGroup.warmup,
  ),
  LiveMode(
    type: TestType.fingerDrag,
    title: 'Finger drag',
    summary: 'Slow, light (${_pct(kFingerDragLoadFraction)}) open-hand drags.',
    icon: Icons.swipe_outlined,
    group: LiveModeGroup.warmup,
  ),
  LiveMode(
    type: TestType.fingerCurl,
    title: 'Finger curls',
    summary:
        'Slow curls at ${_pct(kFingerCurlLoadFraction)}: 3 s up, 3 s down.',
    icon: Icons.back_hand_outlined,
    group: LiveModeGroup.warmup,
  ),
];

/// Mode for [type]; types without their own entry (e.g. guided workout) fall
/// back to free pull.
LiveMode liveModeFor(TestType type) => kLiveModes.firstWhere(
  (m) => m.type == type,
  orElse: () => kLiveModes.first,
);

/// Whether a mode asks for a percentage of the user's max (so the max matters).
bool liveModeUsesMax(TestType t) =>
    t != TestType.custom && t != TestType.peakForce && t != TestType.rfd;

/// Bottom sheet: pick a mode, hand and estimated max. Returns the chosen
/// type, or null if dismissed without picking.
Future<TestType?> showLiveModeSheet(
  BuildContext context, {
  required TestType current,
  required String hand,
  required ValueChanged<String> onHandChanged,
  required double userMaxKg,
  required VoidCallback onEditMax,
}) {
  return showModalBottomSheet<TestType>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _LiveModeSheet(
      current: current,
      hand: hand,
      onHandChanged: onHandChanged,
      userMaxKg: userMaxKg,
      onEditMax: onEditMax,
    ),
  );
}

class _LiveModeSheet extends StatefulWidget {
  const _LiveModeSheet({
    required this.current,
    required this.hand,
    required this.onHandChanged,
    required this.userMaxKg,
    required this.onEditMax,
  });

  final TestType current;
  final String hand;
  final ValueChanged<String> onHandChanged;
  final double userMaxKg;
  final VoidCallback onEditMax;

  @override
  State<_LiveModeSheet> createState() => _LiveModeSheetState();
}

class _LiveModeSheetState extends State<_LiveModeSheet> {
  late String _hand = widget.hand;
  late bool _showAll =
      liveModeFor(widget.current).group != LiveModeGroup.basics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modes = _showAll
        ? kLiveModes
        : kLiveModes.where((m) => m.group == LiveModeGroup.basics).toList();

    final children = <Widget>[];
    LiveModeGroup? lastGroup;
    for (final m in modes) {
      if (_showAll && m.group != lastGroup) {
        lastGroup = m.group;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              m.group.label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
      }
      final selected = m.type == widget.current;
      children.add(
        ListTile(
          key: Key('mode_${m.type.name}'),
          leading: Icon(
            m.icon,
            color: selected ? theme.colorScheme.primary : null,
          ),
          title: Text(
            m.title,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          subtitle: Text(m.summary),
          trailing: selected
              ? Icon(Icons.check, color: theme.colorScheme.primary)
              : null,
          onTap: () => Navigator.of(context).pop(m.type),
        ),
      );
    }
    if (!_showAll) {
      children.add(
        ListTile(
          key: const Key('mode_more'),
          leading: const Icon(Icons.expand_more),
          title: const Text('More modes'),
          subtitle: const Text('Explosive pull, endurance, warm-ups'),
          onTap: () => setState(() => _showAll = true),
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        // A plain column: the list is short, and every tile stays built (so
        // it can be scrolled to and found in tests).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const Text('Hand'),
                    const Spacer(),
                    SegmentedButton<String>(
                      key: const Key('mode_hand'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'Left', label: Text('Left')),
                        ButtonSegment(value: 'Right', label: Text('Right')),
                        ButtonSegment(value: 'Both', label: Text('Both')),
                      ],
                      selected: {_hand},
                      onSelectionChanged: (s) {
                        setState(() => _hand = s.first);
                        widget.onHandChanged(s.first);
                      },
                    ),
                  ],
                ),
              ),
              ListTile(
                key: const Key('mode_edit_max'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: const Text('Your max'),
                subtitle: const Text('Targets in guided modes are a % of this'),
                trailing: Text(
                  '${widget.userMaxKg.toStringAsFixed(0)} kg',
                  style: theme.textTheme.titleMedium,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onEditMax();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Protocol instructions repeat what the strip already shows in big
/// letters: a shouted phase up front ("PULL — …", "WORK rep 2/6 — …") and a
/// countdown at the end ("… 3s"). Drop both.
String plainCoachInstruction(String text, String phase) {
  var t = text.trim();
  // Only a shouted (upper-case) phase word counts, not "Hold steady…".
  if (phase.isNotEmpty && t.startsWith(phase.toUpperCase())) {
    t = t.substring(phase.length).trimLeft();
    if (t.startsWith('—') || t.startsWith('-') || t.startsWith(':')) {
      t = t.substring(1).trimLeft();
    }
  }
  t = t.replaceFirst(RegExp(r'\.\s+\d+\s?s$'), '.');
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}
