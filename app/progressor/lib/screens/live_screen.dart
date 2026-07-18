import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../widgets/protocol_selector.dart';

/// Where force samples come from.
enum SensorSource {
  /// Real Tindeq Progressor over Bluetooth LE.
  progressorBle,
  /// Synthetic / fixture replay (no hardware).
  demo,
}

/// The main live measurement screen.
/// Beautiful large numbers, live plot, controls.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  SensorAdapter? _adapter;
  SensorSource _source = SensorSource.progressorBle;
  List<ForceSample> _samples = [];
  SensorConnectionState _connState = SensorConnectionState.disconnected;
  bool _isRecording = false;
  bool _isConnecting = false;
  String? _statusMessage;
  double? _currentForce;
  double? _peakForce;
  TestType _currentType = TestType.peakForce;
  DateTime? _recordStartTime; // for accurate save timing + gamif

  StreamSubscription<SensorConnectionState>? _stateSub;
  StreamSubscription<SensorSample>? _sampleSub;

  // Warm-up guided mode
  bool _isWarmupMode = false;
  double _targetForce = 0;
  String _warmupInstruction = '';
  int _holdSecondsRemaining = 0;
  Timer? _warmupTimer;
  String _selectedHand = 'Right'; // Left, Right or Both for unilateral focus
  double _onTargetSeconds = 0;
  int _totalFollowSamples = 0;
  double _followMatchPercent = 0; // 0-100 for feedback on curve following

  @override
  void initState() {
    super.initState();
    // Default to real Progressor; demo is still one tap away.
    _useAdapter(TindeqBleAdapter());
  }

  void _useAdapter(SensorAdapter adapter) {
    _stateSub?.cancel();
    _sampleSub?.cancel();
    _adapter = adapter;
    _listen();
  }

  void _listen() {
    _stateSub = _adapter?.state.listen((s) {
      if (!mounted) return;
      setState(() {
        _connState = s;
        if (s == SensorConnectionState.connected) {
          final name = _adapter is TindeqBleAdapter
              ? (_adapter as TindeqBleAdapter).connectedName
              : null;
          _statusMessage = _source == SensorSource.demo
              ? 'Demo connected'
              : (name != null && name.isNotEmpty
                  ? 'Connected: $name'
                  : 'Progressor connected');
          _isConnecting = false;
        } else if (s == SensorConnectionState.disconnected) {
          if (!_isConnecting) _statusMessage = null;
        } else if (s == SensorConnectionState.error) {
          final err = _adapter is TindeqBleAdapter
              ? (_adapter as TindeqBleAdapter).lastError
              : null;
          _statusMessage = err ?? 'Connection error';
          _isConnecting = false;
        } else if (s == SensorConnectionState.connecting) {
          _statusMessage = _source == SensorSource.demo
              ? 'Starting demo…'
              : 'Scanning for Progressor…';
        }
      });
    });
    _sampleSub = _adapter?.samples.listen((s) {
      if (!_isRecording) return;
      if (!mounted) return;
      setState(() {
        _samples = [..._samples, s];
        _currentForce = s.forceKg;
        if (_peakForce == null || s.forceKg > _peakForce!) {
          _peakForce = s.forceKg;
        }
      });
    });
  }

  Future<void> _setSource(SensorSource source) async {
    if (source == _source) return;
    if (_connState == SensorConnectionState.connected || _isConnecting) {
      try {
        await _adapter?.disconnect();
      } catch (_) {}
    }
    _warmupTimer?.cancel();
    _warmupTimer = null;
    setState(() {
      _source = source;
      _connState = SensorConnectionState.disconnected;
      _isConnecting = false;
      _samples = [];
      _currentForce = null;
      _peakForce = null;
      _isRecording = false;
      _recordStartTime = null;
      _isWarmupMode = false;
      _targetForce = 0;
      _warmupInstruction = '';
      _holdSecondsRemaining = 0;
      _statusMessage = source == SensorSource.progressorBle
          ? 'Ready to scan for Progressor'
          : 'Demo mode — no hardware needed';
    });
    _useAdapter(
      source == SensorSource.progressorBle
          ? TindeqBleAdapter()
          : MockReplayAdapter(),
    );
  }

  Future<void> _toggleConnect() async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;

    if (_connState == SensorConnectionState.connected ||
        _connState == SensorConnectionState.connecting ||
        _isConnecting) {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Disconnecting…';
      });
      try {
        if (_adapter is TindeqBleAdapter &&
            (_adapter as TindeqBleAdapter).isMeasuring) {
          await (_adapter as TindeqBleAdapter).stopMeasurement();
        }
        await _adapter?.disconnect();
      } catch (_) {}
      if (!mounted) return;
      _warmupTimer?.cancel();
      _warmupTimer = null;
      setState(() {
        _samples = [];
        _currentForce = null;
        _peakForce = null;
        _isRecording = false;
        _recordStartTime = null;
        _connState = SensorConnectionState.disconnected;
        _statusMessage = null;
        _isWarmupMode = false;
        _targetForce = 0;
        _warmupInstruction = '';
        _holdSecondsRemaining = 0;
      });
      return;
    }

    // Ensure adapter matches selected source.
    if (_source == SensorSource.progressorBle && _adapter is! TindeqBleAdapter) {
      _useAdapter(TindeqBleAdapter());
    } else if (_source == SensorSource.demo && _adapter is! MockReplayAdapter) {
      _useAdapter(MockReplayAdapter());
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = _source == SensorSource.demo
          ? 'Starting demo…'
          : 'Scanning for Progressor… Power it on and keep nearby.';
    });

    try {
      await _adapter?.connect();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connState = SensorConnectionState.error;
        _statusMessage = e.toString().replaceFirst('Exception: ', '');
      });
      messenger?.showSnackBar(
        SnackBar(
          content: Text(_statusMessage ?? 'Connect failed'),
          duration: const Duration(seconds: 5),
          action: _source == SensorSource.progressorBle
              ? SnackBarAction(
                  label: 'Use Demo',
                  onPressed: () => _setSource(SensorSource.demo),
                )
              : null,
        ),
      );
    }
  }

  Future<void> _ensureMeasuring() async {
    if (_adapter is TindeqBleAdapter) {
      final ble = _adapter as TindeqBleAdapter;
      if (!ble.isMeasuring) {
        await ble.startMeasurement();
      }
    }
  }

  Future<void> _startWarmupMode(TestType type) async {
    setState(() {
      _isWarmupMode = true;
      _currentType = type;
      _samples = [];
      _peakForce = null;
      _currentForce = null;
      _isRecording = true;
      _recordStartTime = DateTime.now();
      _holdSecondsRemaining = type == TestType.holdRelease ? 8 : 0;
      _onTargetSeconds = 0;
      _totalFollowSamples = 0;
      _followMatchPercent = 0;
      _targetForce = type.suggestedWarmupPercent * 40; // rough base e.g. ~25-30kg light start; user adjusts or uses feel
    });

    try {
      if (_connState != SensorConnectionState.connected) {
        setState(() {
          _isConnecting = true;
          _statusMessage = _source == SensorSource.demo
              ? 'Starting demo…'
              : 'Scanning for Progressor…';
        });
        await _adapter?.connect();
      }
      await _ensureMeasuring();
      await _adapter?.tare();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isWarmupMode = false;
        _isRecording = false;
        _isConnecting = false;
        _statusMessage = e.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_statusMessage ?? 'Could not start sensor')),
      );
      return;
    }

    _updateWarmupInstruction(type);
    _startWarmupTimer(type);
  }

  void _updateWarmupInstruction(TestType type) {
    switch (type) {
      case TestType.warmupProgressive:
        _warmupInstruction = 'Progressive: Light smooth ramps. 30% → 60-70% over 5-8s. 3-5 reps per hand. Never to failure. Breathe!';
        break;
      case TestType.followCurve:
        _warmupInstruction = 'FOLLOW THE CURVE: Watch the orange target line move. Ramp smoothly, hold steady, release SLOWLY. Match it!';
        _targetForce = 0;
        break;
      case TestType.holdRelease:
        _warmupInstruction = 'HOLD 6-8s at target (~55%), focus tension. Then SLOW CONTROLLED RELEASE (eccentric) 3-5s. Tendon gold!';
        _holdSecondsRemaining = 8;
        break;
      case TestType.fingerDrag:
        _warmupInstruction = 'FINGER DRAG (one hand): Very light ~20-30%. Slow drag fingers across wood ring surface. 6-8s x 4-6. Control > force.';
        break;
      case TestType.fingerCurl:
        _warmupInstruction = 'FINGER CURLS: 3s curl up + 3s slow lower. Light load. 8-12 reps/hand. Prime flexor tendons safely.';
        break;
      default:
        _warmupInstruction = 'Use live chart to guide smooth efforts. Tare first!';
    }
  }

  void _startWarmupTimer(TestType type) {
    _warmupTimer?.cancel();
    if (type == TestType.followCurve) {
      _warmupTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
        if (!_isWarmupMode || !_isRecording) {
          timer.cancel();
          return;
        }
        // 12s cycle for better feel: ramp 0-65% (5s), hold (5s), slow release (2s)
        final elapsedMs = DateTime.now().difference(_recordStartTime!).inMilliseconds % 12000;
        double target = 0;
        String phase = '';
        if (elapsedMs < 5000) {
          target = (elapsedMs / 5000) * 65; // ramp
          phase = 'RAMP UP smoothly';
        } else if (elapsedMs < 10000) {
          target = 65;
          phase = 'HOLD steady';
        } else {
          target = 65 * (1 - (elapsedMs - 10000) / 2000);
          phase = 'SLOW RELEASE';
        }
        // Track match accuracy
        if (_currentForce != null) {
          _totalFollowSamples++;
          final diff = (_currentForce! - target).abs();
          final tol = (target * 0.12).clamp(3.0, 12.0); // ~12% tol or min 3kg
          if (diff <= tol) {
            _onTargetSeconds += 0.12;
          }
          if (_totalFollowSamples > 0) {
            _followMatchPercent = (_onTargetSeconds / (_totalFollowSamples * 0.12) * 100).clamp(0, 100);
          }
        }
        if (mounted) {
          setState(() {
            _targetForce = target;
            if (phase.isNotEmpty && _warmupInstruction.contains('FOLLOW')) {
              _warmupInstruction = 'FOLLOW THE CURVE: $phase • Match orange line!';
            }
          });
        }
      });
    } else if (type == TestType.holdRelease) {
      _warmupTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_isWarmupMode || !_isRecording) {
          timer.cancel();
          return;
        }
        if (_holdSecondsRemaining > 0) {
          setState(() => _holdSecondsRemaining--);
        } else {
          _warmupInstruction = 'SLOW RELEASE — control the lowering for 3-5s!';
          timer.cancel();
        }
      });
    } else if (type == TestType.fingerDrag || type == TestType.fingerCurl || type == TestType.warmupProgressive) {
      // For these, no auto target change; user controls effort. Show periodic encouragement.
      _warmupTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
        if (!_isWarmupMode || !_isRecording) {
          timer.cancel();
          return;
        }
        if (mounted) {
          setState(() {
            // gentle reminder text flip for engagement without overriding user intent
            if (_currentType == TestType.fingerDrag) {
              _warmupInstruction = 'Keep light + slow drag. Breathe. Switch hand soon.';
            } else if (_currentType == TestType.fingerCurl) {
              _warmupInstruction = 'Slow & controlled. Feel the tendons warm. Quality reps.';
            }
          });
        }
      });
    }
  }

  void _stopWarmupMode() {
    _warmupTimer?.cancel();
    _warmupTimer = null;
    final match = _followMatchPercent > 0 ? _followMatchPercent.round() : null;
    setState(() {
      _isWarmupMode = false;
      _targetForce = 0;
      _warmupInstruction = '';
      _holdSecondsRemaining = 0;
      _isRecording = false;
      if (match != null) _followMatchPercent = match.toDouble();
    });
    // If recording had samples, the toggle path will save; here we just reset UI state
  }

  Future<void> _toggleRecord() async {
    // Capture context user before any awaits in async fn (for linter)
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;

    if (_isWarmupMode) {
      // Stop guided warmup - special feedback
      final match = _followMatchPercent;
      final wasFollow = _currentType == TestType.followCurve;
      _stopWarmupMode();
      if (_samples.isNotEmpty) {
        final end = DateTime.now();
        final start = _recordStartTime ?? end.subtract(Duration(milliseconds: _samples.isNotEmpty ? _samples.last.timeMs : 0));
        final computed = computeMetrics(_samples);
        final streak = await _incrementStreakStub();
        final metrics = <String, dynamic>{
          ...computed.toJson(),
          'streakAtSave': streak,
          if (wasFollow) 'warmupMatchPercent': match.round(),
          'warmupType': _currentType.name,
          'hand': _selectedHand,
        };
        final test = PullTest(
          id: const Uuid().v4(),
          startTime: start,
          type: _currentType,
          samples: List.of(_samples),
          endTime: end,
          notes: 'Warm-up • ${_currentType.label} • $_selectedHand hand • ${match > 0 ? "${match.round()}% match" : "guided"}',
          metrics: metrics,
        );
        await TestStorage().save(test);
        if (messenger != null && mounted) {
          final quality = match > 0 ? ' (Match: ${match.round()}%)' : '';
          messenger.showSnackBar(SnackBar(
            content: Text('Warm-up complete! 🔥 Streak +1 ($streak)$quality  Ready to boulder.'),
            duration: const Duration(seconds: 3),
          ));
        }
      }
      _recordStartTime = null;
      return;
    }

    // If a warmup type is selected but not yet in guided mode, launch guided instead of plain record
    if (_currentType.isWarmup && !_isWarmupMode) {
      await _startWarmupMode(_currentType);
      if (messenger != null && mounted && _isWarmupMode) {
        messenger.showSnackBar(const SnackBar(content: Text('Guided warm-up started — follow instructions!'), duration: Duration(seconds: 1)));
      }
      return;
    }

    if (!_isRecording) {
      // start fresh plain record
      final now = DateTime.now();
      setState(() {
        _samples = [];
        _peakForce = null;
        _currentForce = null;
        _isRecording = true;
        _recordStartTime = now;
      });
      try {
        if (_connState != SensorConnectionState.connected) {
          setState(() {
            _isConnecting = true;
            _statusMessage = _source == SensorSource.demo
                ? 'Starting demo…'
                : 'Scanning for Progressor…';
          });
          await _adapter?.connect();
        }
        await _ensureMeasuring();
        await _adapter?.tare();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _recordStartTime = null;
          _isConnecting = false;
          _statusMessage = e.toString().replaceFirst('Exception: ', '');
        });
        messenger?.showSnackBar(
          SnackBar(content: Text(_statusMessage ?? 'Could not start sensor')),
        );
        return;
      }
    } else {
      setState(() => _isRecording = false);
      if (_adapter is TindeqBleAdapter) {
        try {
          await (_adapter as TindeqBleAdapter).stopMeasurement();
        } catch (_) {}
      }
      if (_samples.isNotEmpty) {
        // Proper timing for save (C6)
        final end = DateTime.now();
        final start = _recordStartTime ??
            end.subtract(Duration(milliseconds: _samples.last.timeMs));

        // Compute rich metrics
        final computed = computeMetrics(_samples);
        final peakKg = computed.peakKg;

        // Gamification on save (streak increment stub, PR detection) per C6
        final previous = await TestStorage().loadAll();
        final prevMax = previous.isEmpty
            ? 0.0
            : previous
                .map((p) => p.peakForceKg ?? 0.0)
                .reduce((a, b) => max(a, b));
        final isNewPR = peakKg != null && peakKg > prevMax;

        final streak = await _incrementStreakStub();

        final metrics = <String, dynamic>{
          ...computed.toJson(),
          'isPR': isNewPR,
          'streakAtSave': streak,
        };

        final test = PullTest(
          id: const Uuid().v4(),
          startTime: start,
          type: _currentType,
          samples: List.of(_samples),
          endTime: end,
          notes: 'Recorded in Progressor',
          metrics: metrics,
        );
        await TestStorage().save(test);

        if (messenger != null && mounted) {
          final msg = isNewPR
              ? '🎉 Test saved! NEW PR! 🔥 Streak +1 ($streak)'
              : 'Test saved! 🔥 Streak +1 ($streak). View in History.';
          messenger.showSnackBar(SnackBar(content: Text(msg)));
        }
      }
      _recordStartTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connState == SensorConnectionState.connected;
    final busy = _isConnecting || _connState == SensorConnectionState.connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showWarmupGuide,
            tooltip: 'Warm-up Guide & Resources',
          ),
          IconButton(
            icon: Icon(
              isConnected
                  ? (_source == SensorSource.demo
                      ? Icons.science
                      : Icons.bluetooth_connected)
                  : Icons.bluetooth,
              color: isConnected
                  ? Colors.greenAccent
                  : (_connState == SensorConnectionState.error
                      ? Colors.redAccent
                      : null),
            ),
            onPressed: busy ? null : _toggleConnect,
            tooltip: isConnected
                ? 'Disconnect'
                : (_source == SensorSource.demo
                    ? 'Start demo'
                    : 'Scan & connect Progressor'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _samples = [];
              _peakForce = null;
              _recordStartTime = null;
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    // Sensor source: real Progressor vs demo
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<SensorSource>(
                            segments: const [
                              ButtonSegment(
                                value: SensorSource.progressorBle,
                                label: Text('Progressor'),
                                icon: Icon(Icons.bluetooth, size: 18),
                              ),
                              ButtonSegment(
                                value: SensorSource.demo,
                                label: Text('Demo'),
                                icon: Icon(Icons.science, size: 18),
                              ),
                            ],
                            selected: {_source},
                            onSelectionChanged: busy || isConnected
                                ? null
                                : (s) => _setSource(s.first),
                          ),
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _statusMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: _connState == SensorConnectionState.error
                                    ? Colors.redAccent
                                    : Colors.white70,
                              ),
                            ),
                          ] else if (!isConnected) ...[
                            const SizedBox(height: 6),
                            Text(
                              _source == SensorSource.progressorBle
                                  ? 'Power on your Progressor, then Connect'
                                  : 'Demo replays synthetic force data',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white54),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Big beautiful force display + warmup match feedback
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          Text(
                            _currentForce != null
                                ? _currentForce!.toStringAsFixed(1)
                                : '—',
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                  fontSize: 72,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  color: _isWarmupMode &&
                                          _targetForce > 0 &&
                                          _currentForce != null
                                      ? ((_currentForce! - _targetForce)
                                                  .abs() <
                                              (_targetForce * 0.15)
                                                  .clamp(3, 15)
                                          ? Colors.greenAccent
                                          : null)
                                      : null,
                                ),
                          ),
                          const Text('kg',
                              style: TextStyle(
                                  fontSize: 20, color: Colors.white70)),
                          if (_isWarmupMode && _targetForce > 0)
                            Text(
                              'target ${_targetForce.toStringAsFixed(1)} kg',
                              style: const TextStyle(
                                  color: Colors.orangeAccent, fontSize: 14),
                            ),
                          if (_peakForce != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'PEAK ${_peakForce!.toStringAsFixed(1)} kg',
                                style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Live pretty plot
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LiveForceChart(
                        samples: _samples,
                        targetForceKg: _isWarmupMode && _targetForce > 0
                            ? _targetForce
                            : null,
                        peakForceKg: _peakForce,
                        height: 160,
                      ),
                    ),

                    if (_isWarmupMode && _targetForce > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'TARGET ${_targetForce.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),

                    const SizedBox(height: 8),

                    ProtocolSelector(
                      current: _currentType,
                      onChanged: (t) => setState(() => _currentType = t),
                    ),

                    if (_currentType.isWarmup || _isWarmupMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Hand: ',
                                style: TextStyle(fontSize: 12)),
                            ChoiceChip(
                              label: const Text('Left'),
                              selected: _selectedHand == 'Left',
                              onSelected: (_) =>
                                  setState(() => _selectedHand = 'Left'),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('Right'),
                              selected: _selectedHand == 'Right',
                              onSelected: (_) =>
                                  setState(() => _selectedHand = 'Right'),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('Both'),
                              selected: _selectedHand == 'Both',
                              onSelected: (_) =>
                                  setState(() => _selectedHand = 'Both'),
                            ),
                          ],
                        ),
                      ),

                    if (_isWarmupMode)
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              Colors.orangeAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.orangeAccent
                                  .withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.accessibility_new,
                                    color: Colors.orangeAccent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _currentType.label,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orangeAccent),
                                  ),
                                ),
                                if (_holdSecondsRemaining > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.orangeAccent,
                                        borderRadius:
                                            BorderRadius.circular(4)),
                                    child: Text(
                                        'HOLD ${_holdSecondsRemaining}s',
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(_warmupInstruction,
                                style: const TextStyle(fontSize: 14)),
                            if (_followMatchPercent > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    'Match quality: ${_followMatchPercent.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                            const SizedBox(height: 8),
                            if (_currentType == TestType.followCurve ||
                                _currentType == TestType.holdRelease)
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: () => setState(() =>
                                        _targetForce =
                                            (_targetForce - 3).clamp(5, 120)),
                                    child: const Text('-3kg'),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton(
                                    onPressed: () => setState(() =>
                                        _targetForce =
                                            (_targetForce + 3).clamp(5, 120)),
                                    child: const Text('+3kg'),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Adjust target',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70)),
                                ],
                              ),
                          ],
                        ),
                      )
                    else if (_currentType.isWarmup)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: FilledButton.icon(
                          onPressed: () =>
                              unawaited(_startWarmupMode(_currentType)),
                          icon: const Icon(Icons.play_circle),
                          label: Text(
                              'START GUIDED ${_currentType.label.toUpperCase()}'),
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black),
                        ),
                      ),

                    if (!_isWarmupMode && !_isRecording)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                                'Quick Warm-ups (tap to start guided)',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white70)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                _quickWarmupChip(
                                    TestType.fingerDrag, 'Drag'),
                                _quickWarmupChip(
                                    TestType.fingerCurl, 'Curls'),
                                _quickWarmupChip(
                                    TestType.followCurve, 'Curve'),
                                _quickWarmupChip(
                                    TestType.holdRelease, 'Hold+Rel'),
                                _quickWarmupChip(
                                    TestType.warmupProgressive, 'Prog'),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Controls pinned to bottom
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : _toggleConnect,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isConnected
                            ? Icons.link_off
                            : (_source == SensorSource.demo
                                ? Icons.science
                                : Icons.bluetooth_searching)),
                    label: Text(
                      busy
                          ? 'Scanning…'
                          : (isConnected
                              ? 'Disconnect'
                              : (_source == SensorSource.demo
                                  ? 'Start Demo'
                                  : 'Connect')),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : _toggleRecord,
                    icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                    label: Text(_isRecording
                        ? (_isWarmupMode ? 'FINISH WARM-UP' : 'STOP')
                        : (_currentType.isWarmup
                            ? 'START WARM-UP'
                            : 'START')),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _isRecording ? Colors.redAccent : null,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: (!isConnected || busy)
                        ? null
                        : () async {
                            final m = mounted
                                ? ScaffoldMessenger.of(context)
                                : null;
                            try {
                              await _adapter?.tare();
                              if (m != null && mounted) {
                                m.showSnackBar(
                                  const SnackBar(
                                    content: Text('Tared'),
                                    duration: Duration(milliseconds: 800),
                                  ),
                                );
                              }
                            } catch (e) {
                              m?.showSnackBar(
                                SnackBar(content: Text('Tare failed: $e')),
                              );
                            }
                          },
                    icon: const Icon(Icons.balance),
                    label: const Text('TARE'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _warmupTimer?.cancel();
    _stateSub?.cancel();
    _sampleSub?.cancel();
    _adapter?.disconnect();
    super.dispose();
  }

  /// Streak increment stub for gamification on save (C6).
  /// Always increments for demo/stub; real impl would check dates.
  Future<int> _incrementStreakStub() async {
    final prefs = await SharedPreferences.getInstance();
    int s = prefs.getInt('gamif_streak') ?? 0;
    s += 1;
    await prefs.setInt('gamif_streak', s);
    return s;
  }

  Widget _quickWarmupChip(TestType type, String short) {
    return ActionChip(
      avatar: const Icon(Icons.accessibility_new, size: 16),
      label: Text(short),
      onPressed: () {
        setState(() => _currentType = type);
        unawaited(_startWarmupMode(type));
      },
    );
  }

  void _showWarmupGuide() {
    final resources = <_Resource>[
      _Resource(
        'Your Setup: One-Hand Wood Ring on Board',
        'Standing board + single Metolius Wood Rock Rings II (or similar). Unilateral pulls great for detecting imbalances. Use legs to fine-tune load.',
        'https://www.climbing.com/gear/2020-gym-training-kit-metolius-wood-rock-rings-review/',
        'assets/images/ring_pull_setup.jpg',
      ),
      _Resource(
        'Lattice: Finger Strength & Grips',
        'Progressive overload every session. Front-3 drag excellent for open-hand wood rings. Build-up sets before intensity. 1-arm for advanced.',
        'https://latticetraining.com/blog/how-to-manage-finger-strength-for-climbers',
        null,
      ),
      _Resource(
        'Follow the Force Curve & Contact Strength',
        'Train RFD + control across the force-time curve. Spectrum from isolated to climbing-specific. Use our Follow the Curve mode!',
        'https://www.powercompanyclimbing.com/blog/contact-strength-spectrum',
        'assets/images/force_curve.jpg',
      ),
      _Resource(
        'One-Hand Hangboard Protocol (advanced context)',
        'Thorough 20-30min progressive warm-up before one-arm work. Start light. Listen to body.',
        'https://trainingforclimbing.com/advanced-hangboard-training-technique/',
        null,
      ),
      _Resource(
        'Finger Curls & Rolls for Climbers',
        'Excellent tendon prep. Slow controlled. Complements drags.',
        'https://stevenlow.org/finger-rolls-for-climbing-hand-strength-and-hangboard/',
        'assets/images/finger_curl.jpg',
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🧗 Warm-up Guide: Wood Rings + Bouldering'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Optimized for your Metolius wood ring + one-hand board setup before bouldering sessions. 5-12 min focused activation.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                const Text('Key principles (research-backed):', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('• Progressive only — never max or failure when cold.\n• 30-60% efforts for most warm-up work.\n• Prioritize smooth control & slow eccentrics (tendon health).\n• One hand at a time — note left/right differences.\n• Finish with 3-5 easy boulders building to your session.'),
                const SizedBox(height: 12),
                const Text('Exercises with visuals & links:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                for (final r in resources) _resourceCard(ctx, r),
                const SizedBox(height: 10),
                const Text('Also excellent: https://trainingforclimbing.com/finger-warm-ups/  •  Reddit r/climbharder warm-up threads'),
                const SizedBox(height: 6),
                const Text('Use the Quick Warm-ups chips + Follow Curve / Hold+Release in this screen for guided practice with live feedback.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('https://latticetraining.com/blog/how-to-manage-finger-strength-for-climbers')),
            child: const Text('Lattice Guide'),
          ),
        ],
      ),
    );
  }

  Widget _resourceCard(BuildContext ctx, _Resource r) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(r.url)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (r.imageAsset != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(r.imageAsset!, height: 110, fit: BoxFit.cover),
                  ),
                ),
              Text(r.desc, style: const TextStyle(fontSize: 12)),
              Text(r.url, style: const TextStyle(fontSize: 10, color: Colors.blue)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Resource {
  final String title;
  final String desc;
  final String url;
  final String? imageAsset;
  _Resource(this.title, this.desc, this.url, this.imageAsset);
}