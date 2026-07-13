import 'package:flutter/material.dart';
import '../screens/live_screen.dart';
import '../screens/history_screen.dart';
import '../screens/train_screen.dart';
import '../screens/more_screen.dart';

/// Adaptive shell with sidebar on wide screens, bottom nav on narrow.
/// Inspired by Flowlog.
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _index = 0;

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
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final useRail = width >= 600;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
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
            Expanded(child: _pages[_index]),
          ],
        ),
      );
    }

    // Bottom nav for phones / narrow
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: List.generate(_labels.length, (i) {
          return NavigationDestination(
            icon: Icon(_icons[i]),
            label: _labels[i],
          );
        }),
      ),
    );
  }
}
