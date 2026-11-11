import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kOnboardingDoneKey = 'onboarding_v1_done';

/// First-run welcome: one screen, one button. Connecting a gauge (or trying
/// the demo) happens on Live, where the user lands next.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOnboardingDoneKey, true);
    } catch (_) {}
    onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/ring_pull_setup.jpg',
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(height: 120),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Progressor',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pull on your Tindeq Progressor and watch the force live: '
                    'the number now, your peak, and the curve. '
                    'No gauge yet? Try the demo on the next screen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    key: const Key('onboarding_start'),
                    onPressed: _finish,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Get started'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
