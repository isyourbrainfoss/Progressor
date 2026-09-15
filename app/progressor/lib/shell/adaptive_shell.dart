import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/history_screen.dart';
import '../screens/live_screen.dart';
import '../screens/more_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/train_screen.dart';

class _GoTabIntent extends Intent {
  const _GoTabIntent(this.index);
  final int index;
}

class _HelpIntent extends Intent {
  const _HelpIntent();
}

/// Adaptive shell with sidebar on wide screens, bottom nav on narrow.
/// Inspired by Flowlog.
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _index = 0;
  bool _checkingOnboarding = true;
  bool _showOnboarding = false;

  final _pages = const [
    LiveScreen(),
    HistoryScreen(),
    TrainScreen(),
    MoreScreen(),
  ];

  final _labels = const ['Live', 'History', 'Train', 'More'];
  final _icons = const [
    Icons.show_chart,
    Icons.history,
    Icons.fitness_center,
    Icons.more_horiz,
  ];

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(kOnboardingDoneKey) ?? false;
      if (!mounted) return;
      setState(() {
        _showOnboarding = !done;
        _checkingOnboarding = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showOnboarding = false;
        _checkingOnboarding = false;
      });
    }
  }

  void _go(int i) {
    if (i < 0 || i >= _pages.length) return;
    setState(() => _index = i);
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: const Text(
          '1 / Ctrl+L    Live\n'
          '2 / Ctrl+H    History\n'
          '3             Train\n'
          '4             More\n'
          'Space         Start / stop (Live)\n'
          'T             Tare (Live)\n'
          'F1 or ?       This help',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingOnboarding) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_showOnboarding) {
      return OnboardingScreen(
        onFinished: () => setState(() => _showOnboarding = false),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final useRail = width >= 600;

    final body = IndexedStack(
      index: _index,
      children: _pages,
    );

    final scaffold = useRail
        ? Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _go,
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(_labels.length, (i) {
                    return NavigationRailDestination(
                      icon: Icon(_icons[i]),
                      selectedIcon: Icon(_icons[i]),
                      label: Text(_labels[i]),
                    );
                  }),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          )
        : Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _go,
              destinations: List.generate(_labels.length, (i) {
                return NavigationDestination(
                  icon: Icon(_icons[i]),
                  label: _labels[i],
                );
              }),
            ),
          );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.digit1): _GoTabIntent(0),
        SingleActivator(LogicalKeyboardKey.digit2): _GoTabIntent(1),
        SingleActivator(LogicalKeyboardKey.digit3): _GoTabIntent(2),
        SingleActivator(LogicalKeyboardKey.digit4): _GoTabIntent(3),
        SingleActivator(LogicalKeyboardKey.keyL, control: true): _GoTabIntent(0),
        SingleActivator(LogicalKeyboardKey.keyH, control: true): _GoTabIntent(1),
        SingleActivator(LogicalKeyboardKey.f1): _HelpIntent(),
        SingleActivator(LogicalKeyboardKey.slash, shift: true): _HelpIntent(),
      },
      child: Actions(
        actions: {
          _GoTabIntent: CallbackAction<_GoTabIntent>(
            onInvoke: (i) {
              _go(i.index);
              return null;
            },
          ),
          _HelpIntent: CallbackAction<_HelpIntent>(
            onInvoke: (_) {
              _showHelp();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: scaffold,
        ),
      ),
    );
  }
}
