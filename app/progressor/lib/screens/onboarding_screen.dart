import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sensors/sensor_hub.dart';
import 'sensors_screen.dart';

const kOnboardingDoneKey = 'onboarding_v1_done';

/// First-run tour. Does not force demo mode if a Progressor is already paired.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingDoneKey, true);
    widget.onFinished();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hub = SensorHubScope.maybeOf(context);
    final paired = hub?.hasProgressor ?? false;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _pageBody(
                    image: 'assets/images/ring_pull_setup.jpg',
                    title: 'Progressor',
                    body:
                        'Live force, guided warm-ups, and a history that '
                        'survives restarts — built for a Tindeq Progressor 200.',
                  ),
                  _pageBody(
                    image: 'assets/images/force_curve.jpg',
                    title: 'Train with a curve',
                    body:
                        'Peak, RFD, repeaters, and wood-ring warm-ups. '
                        'Follow the orange target, then pinch-zoom your pull '
                        'in History.',
                  ),
                  _pairPage(paired),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white24,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_index < 2) {
                      _page.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      );
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_index < 2 ? 'Next' : 'Get started'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageBody({
    required String image,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              image,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(height: 120),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _pairPage(bool paired) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Icon(
            paired ? Icons.check_circle : Icons.sensors,
            size: 72,
            color: paired ? Colors.greenAccent : Colors.orangeAccent,
          ),
          const SizedBox(height: 16),
          Text(
            paired ? 'Progressor is paired' : 'Connect your Progressor',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            paired
                ? 'You are ready to measure real force. Demo mode stays off '
                    'while a device is connected.'
                : 'Pair from Live or Sensors. You can try a synthetic demo '
                    'later — it will switch off automatically when a real '
                    'Progressor connects.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
            textAlign: TextAlign.center,
          ),
          if (!paired) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SensorsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Open Sensors'),
            ),
          ],
        ],
      ),
    );
  }
}
