import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../sensors/sensor_hub.dart';
import '../widgets/protocol_selector.dart';
import 'sensors_screen.dart';

/// Live measurement screen — real Progressor via [SensorHub], optional Demo.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  /// Demo-only adapter (null when using hub Progressor).
  SensorAdapter? _demoAdapter;
  bool _demoMode = false;

  List<ForceSample> _samples = [];
  bool _isRecording = false;
  double? _currentForce;
  double? _peakForce;
  TestType _currentType = TestType.peakForce;
  DateTime? _recordStartTime;

  StreamSubscription<SensorSample>? _sampleSub;
  SensorAdapter? _listeningAdapter;
  SensorHub? _hub;
  bool _hubListening = false;

  // Warm-up guided mode
  bool _isWarmupMode = false;
  double _targetForce = 0;
  String _warmupInstruction = '';
  int _holdSecondsRemaining = 0;
  Timer? _warmupTimer;
  String _selectedHand = 'Right';
  double _onTargetSeconds = 0;
  int _totalFollowSamples = 0;
  double _followMatchPercent = 0;

  SensorAdapter? get _activeAdapter {
    if (_demoMode) return _demoAdapter;
    return _hub?.activeAdapter;
  }

  bool get _isConnected {
    if (_demoMode) {
      return _demoAdapter != null;
    }
    return _hub?.isProgressorConnected ?? false;
  }

  bool get _isConnecting {
    return !_demoMode &&
        _hub?.progressorState == SensorConnectionState.connecting;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hub = SensorHubScope.maybeOf(context);
    if (hub != _hub) {
      if (_hubListening) {
        _hub?.removeListener(_onHubChanged);
        _hubListening = false;
      }
      _hub = hub;
      _hub?.addListener(_onHubChanged);
      _hubListening = hub != null;
    }
    _syncSampleListener();
  }

  void _onHubChanged() {
    if (!mounted) return;
    _syncSampleListener();
    setState(() {});
  }

  void _syncSampleListener() {
    final adapter = _activeAdapter;
    if (identical(adapter, _listeningAdapter)) return;
    _sampleSub?.cancel();
    _listeningAdapter = adapter;
    _sampleSub = adapter?.samples.listen((s) {
      if (!_isRecording || !mounted) return;
      setState(() {
        _samples = [..._samples, s];
        _currentForce = s.forceKg;
        if (_peakForce == null || s.forceKg > _peakForce!) {
          _peakForce = s.forceKg;
        }
      });
    });
  }

  Future<void> _openSensors() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SensorsScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pairOrScan() async {
    final hub = _hub;
    if (hub == null) return;
    // Exit demo when pairing real hardware.
    await _exitDemoMode();
    await runProgressorScanFlow(context, hub);
    if (!mounted) return;
    final p = hub.progressor;
    if (p != null && p.hasBleId && p.state != SensorConnectionState.connected) {
      await hub.connect(p.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _reconnect() async {
    final hub = _hub;
    final p = hub?.progressor;
    if (hub == null || p == null) return;
    await _exitDemoMode();
    if (!p.hasBleId) {
      await runProgressorScanFlow(context, hub);
    }
    if (hub.progressor?.hasBleId == true) {
      await hub.connect(hub.progressor!.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _disconnectHardware() async {
    final hub = _hub;
    final p = hub?.progressor;
    if (hub == null || p == null) return;
    await hub.disconnect(p.id);
    if (mounted) setState(() {});
  }

  Future<void> _enterDemoMode() async {
    final hub = _hub;
    if (hub?.isProgressorConnected == true && hub!.progressor != null) {
      await hub.disconnect(hub.progressor!.id);
    }
    await _demoAdapter?.disconnect();
    _demoAdapter = MockReplayAdapter();
    setState(() => _demoMode = true);
    _syncSampleListener();
    try {
      await _demoAdapter!.connect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo mode — synthetic force data'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demo failed: $e')),
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _exitDemoMode() async {
    if (!_demoMode) return;
    try {
      await _demoAdapter?.disconnect();
    } catch (_) {}
    _demoAdapter = null;
    setState(() => _demoMode = false);
    _syncSampleListener();
  }

  Future<void> _ensureHardwareReady() async {
    if (_demoMode) {
      if (_demoAdapter == null) {
        _demoAdapter = MockReplayAdapter();
        await _demoAdapter!.connect();
        _syncSampleListener();
      }
      return;
    }

    final hub = _hub;
    if (hub == null) {
      throw Exception('Sensor hub unavailable');
    }
    if (!hub.hasProgressor || hub.progressor?.hasBleId != true) {
      await runProgressorScanFlow(context, hub);
    }
    if (hub.progressor?.hasBleId != true) {
      throw Exception(
        hub.lastError ??
            'No Progressor paired. Open Sensors and tap Add Progressor.',
      );
    }
    if (!hub.isProgressorConnected) {
      await hub.connect(hub.progressor!.id);
    }
    if (!hub.isProgressorConnected) {
      throw Exception(
        hub.lastError ?? 'Could not connect to Progressor. Check Bluetooth.',
      );
    }
    _syncSampleListener();
  }

  Future<void> _ensureMeasuring() async {
    final ble = _activeAdapter is TindeqBleAdapter
        ? _activeAdapter as TindeqBleAdapter
        : null;
    if (ble != null && !ble.isMeasuring) {
      await ble.startMeasurement();
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
      _targetForce = type.suggestedWarmupPercent * 40;
    });

    try {
      await _ensureHardwareReady();
      await _ensureMeasuring();
      await _activeAdapter?.tare();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isWarmupMode = false;
        _isRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return;
    }

    _updateWarmupInstruction(type);
    _startWarmupTimer(type);
  }

  void _updateWarmupInstruction(TestType type) {
    switch (type) {
      case TestType.warmupProgressive:
        _warmupInstruction =
            'Progressive: Light smooth ramps. 30% → 60-70% over 5-8s. 3-5 reps per hand. Never to failure. Breathe!';
      case TestType.followCurve:
        _warmupInstruction =
            'FOLLOW THE CURVE: Watch the orange target line move. Ramp smoothly, hold steady, release SLOWLY. Match it!';
        _targetForce = 0;
      case TestType.holdRelease:
        _warmupInstruction =
            'HOLD 6-8s at target (~55%), focus tension. Then SLOW CONTROLLED RELEASE (eccentric) 3-5s. Tendon gold!';
        _holdSecondsRemaining = 8;
      case TestType.fingerDrag:
        _warmupInstruction =
            'FINGER DRAG (one hand): Very light ~20-30%. Slow drag fingers across wood ring surface. 6-8s x 4-6. Control > force.';
      case TestType.fingerCurl:
        _warmupInstruction =
            'FINGER CURLS: 3s curl up + 3s slow lower. Light load. 8-12 reps/hand. Prime flexor tendons safely.';
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
        final elapsedMs =
            DateTime.now().difference(_recordStartTime!).inMilliseconds % 12000;
        double target = 0;
        String phase = '';
        if (elapsedMs < 5000) {
          target = (elapsedMs / 5000) * 65;
          phase = 'RAMP UP smoothly';
        } else if (elapsedMs < 10000) {
          target = 65;
          phase = 'HOLD steady';
        } else {
          target = 65 * (1 - (elapsedMs - 10000) / 2000);
          phase = 'SLOW RELEASE';
        }
        if (_currentForce != null) {
          _totalFollowSamples++;
          final diff = (_currentForce! - target).abs();
          final tol = (target * 0.12).clamp(3.0, 12.0);
          if (diff <= tol) _onTargetSeconds += 0.12;
          if (_totalFollowSamples > 0) {
            _followMatchPercent =
                (_onTargetSeconds / (_totalFollowSamples * 0.12) * 100)
                    .clamp(0, 100);
          }
        }
        if (mounted) {
          setState(() {
            _targetForce = target;
            if (phase.isNotEmpty && _warmupInstruction.contains('FOLLOW')) {
              _warmupInstruction =
                  'FOLLOW THE CURVE: $phase • Match orange line!';
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
          _warmupInstruction =
              'SLOW RELEASE — control the lowering for 3-5s!';
          timer.cancel();
        }
      });
    } else if (type == TestType.fingerDrag ||
        type == TestType.fingerCurl ||
        type == TestType.warmupProgressive) {
      _warmupTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
        if (!_isWarmupMode || !_isRecording) {
          timer.cancel();
          return;
        }
        if (mounted) {
          setState(() {
            if (_currentType == TestType.fingerDrag) {
              _warmupInstruction =
                  'Keep light + slow drag. Breathe. Switch hand soon.';
            } else if (_currentType == TestType.fingerCurl) {
              _warmupInstruction =
                  'Slow & controlled. Feel the tendons warm. Quality reps.';
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
  }

  Future<void> _toggleRecord() async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;

    if (_isWarmupMode) {
      final match = _followMatchPercent;
      final wasFollow = _currentType == TestType.followCurve;
      _stopWarmupMode();
      final ble = _activeAdapter is TindeqBleAdapter
          ? _activeAdapter as TindeqBleAdapter
          : null;
      try {
        await ble?.stopMeasurement();
      } catch (_) {}
      if (_samples.isNotEmpty) {
        final end = DateTime.now();
        final start = _recordStartTime ??
            end.subtract(
              Duration(
                milliseconds: _samples.isNotEmpty ? _samples.last.timeMs : 0,
              ),
            );
        final computed = computeMetrics(_samples);
        final streak = await _incrementStreakStub();
        final metrics = <String, dynamic>{
          ...computed.toJson(),
          'streakAtSave': streak,
          if (wasFollow) 'warmupMatchPercent': match.round(),
          'warmupType': _currentType.name,
          'hand': _selectedHand,
          'source': _demoMode ? 'demo' : 'progressor',
        };
        final test = PullTest(
          id: const Uuid().v4(),
          startTime: start,
          type: _currentType,
          samples: List.of(_samples),
          endTime: end,
          notes:
              'Warm-up • ${_currentType.label} • $_selectedHand hand • ${match > 0 ? "${match.round()}% match" : "guided"}',
          metrics: metrics,
        );
        await TestStorage().save(test);
        if (messenger != null && mounted) {
          final quality = match > 0 ? ' (Match: ${match.round()}%)' : '';
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Warm-up complete! 🔥 Streak +1 ($streak)$quality  Ready to boulder.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
      _recordStartTime = null;
      return;
    }

    if (_currentType.isWarmup && !_isWarmupMode) {
      await _startWarmupMode(_currentType);
      if (messenger != null && mounted && _isWarmupMode) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Guided warm-up started — follow instructions!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    if (!_isRecording) {
      final now = DateTime.now();
      setState(() {
        _samples = [];
        _peakForce = null;
        _currentForce = null;
        _isRecording = true;
        _recordStartTime = now;
      });
      try {
        await _ensureHardwareReady();
        await _ensureMeasuring();
        await _activeAdapter?.tare();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _recordStartTime = null;
        });
        messenger?.showSnackBar(SnackBar(content: Text('$e')));
        return;
      }
    } else {
      setState(() => _isRecording = false);
      final ble = _activeAdapter is TindeqBleAdapter
          ? _activeAdapter as TindeqBleAdapter
          : null;
      try {
        await ble?.stopMeasurement();
      } catch (_) {}
      if (_samples.isNotEmpty) {
        final end = DateTime.now();
        final start = _recordStartTime ??
            end.subtract(Duration(milliseconds: _samples.last.timeMs));
        final computed = computeMetrics(_samples);
        final peakKg = computed.peakKg;
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
          'source': _demoMode ? 'demo' : 'progressor',
        };
        final test = PullTest(
          id: const Uuid().v4(),
          startTime: start,
          type: _currentType,
          samples: List.of(_samples),
          endTime: end,
          notes: _demoMode ? 'Demo recording' : 'Recorded in Progressor',
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
    final hub = _hub;
    final connected = _isConnected;
    final busy = _isConnecting;

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
            icon: const Icon(Icons.sensors),
            onPressed: _openSensors,
            tooltip: 'Sensors',
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: _SensorStatusBanner(
                        demoMode: _demoMode,
                        hub: hub,
                        busy: busy,
                        onPair: _pairOrScan,
                        onReconnect: _reconnect,
                        onDisconnect: _disconnectHardware,
                        onOpenSensors: _openSensors,
                        onDemo: _enterDemoMode,
                        onExitDemo: _exitDemoMode,
                      ),
                    ),

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
                          const Text(
                            'kg',
                            style:
                                TextStyle(fontSize: 20, color: Colors.white70),
                          ),
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
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

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
                            fontWeight: FontWeight.bold,
                          ),
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
                            const Text('Hand: ', style: TextStyle(fontSize: 12)),
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
                          color: Colors.orangeAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orangeAccent.withValues(alpha: 0.5),
                          ),
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
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ),
                                if (_holdSecondsRemaining > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'HOLD ${_holdSecondsRemaining}s',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            if (_currentType == TestType.followCurve ||
                                _currentType == TestType.holdRelease) ...[
                              const SizedBox(height: 8),
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
                                ],
                              ),
                            ],
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
                            'START GUIDED ${_currentType.label.toUpperCase()}',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                          ),
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
                                  fontSize: 11, color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                _quickWarmupChip(TestType.fingerDrag, 'Drag'),
                                _quickWarmupChip(TestType.fingerCurl, 'Curls'),
                                _quickWarmupChip(TestType.followCurve, 'Curve'),
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

            // Controls
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_demoMode)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : () => unawaited(_exitDemoMode()),
                      icon: const Icon(Icons.science),
                      label: const Text('Exit Demo'),
                    )
                  else if (connected)
                    FilledButton.tonalIcon(
                      onPressed:
                          busy ? null : () => unawaited(_disconnectHardware()),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => unawaited(
                                (hub?.hasProgressor ?? false)
                                    ? _reconnect()
                                    : _pairOrScan(),
                              ),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              (hub?.hasProgressor ?? false)
                                  ? Icons.bluetooth_searching
                                  : Icons.sensors,
                            ),
                      label: Text(
                        busy
                            ? 'Connecting…'
                            : ((hub?.hasProgressor ?? false)
                                ? 'Connect'
                                : 'Pair'),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : _toggleRecord,
                    icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      _isRecording
                          ? (_isWarmupMode ? 'FINISH WARM-UP' : 'STOP')
                          : (_currentType.isWarmup
                              ? 'START WARM-UP'
                              : 'START'),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _isRecording ? Colors.redAccent : null,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: (!connected || busy)
                        ? null
                        : () async {
                            final m = mounted
                                ? ScaffoldMessenger.of(context)
                                : null;
                            try {
                              await _activeAdapter?.tare();
                              m?.showSnackBar(
                                const SnackBar(
                                  content: Text('Tared'),
                                  duration: Duration(milliseconds: 800),
                                ),
                              );
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

  Future<int> _incrementStreakStub() async {
    final prefs = await SharedPreferences.getInstance();
    int s = prefs.getInt('gamif_streak') ?? 0;
    s += 1;
    await prefs.setInt('gamif_streak', s);
    return s;
  }

  void _showWarmupGuide() {
    final resources = <_Resource>[
      _Resource(
        'Your Setup: One-Hand Wood Ring on Board',
        'Standing board + single Metolius Wood Rock Rings II (or similar). Unilateral pulls great for detecting imbalances.',
        'https://www.climbing.com/gear/2020-gym-training-kit-metolius-wood-rock-rings-review/',
        'assets/images/ring_pull_setup.jpg',
      ),
      _Resource(
        'Lattice: Finger Strength & Grips',
        'Progressive overload every session. Front-3 drag excellent for open-hand wood rings.',
        'https://latticetraining.com/blog/how-to-manage-finger-strength-for-climbers',
        null,
      ),
      _Resource(
        'Follow the Force Curve & Contact Strength',
        'Train RFD + control across the force-time curve. Use Follow the Curve mode!',
        'https://www.powercompanyclimbing.com/blog/contact-strength-spectrum',
        'assets/images/force_curve.jpg',
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
                  'Optimized for wood ring + one-hand board setup before bouldering. 5-12 min activation.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                for (final r in resources) _resourceCard(ctx, r),
              ],
            ),
          ),
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
                    child: Image.asset(r.imageAsset!,
                        height: 110, fit: BoxFit.cover),
                  ),
                ),
              Text(r.desc, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_hubListening) {
      _hub?.removeListener(_onHubChanged);
      _hubListening = false;
    }
    _warmupTimer?.cancel();
    _sampleSub?.cancel();
    unawaited(_demoAdapter?.disconnect() ?? Future.value());
    super.dispose();
  }
}

/// Flowlog-style readiness banner: Pair / Reconnect / Connected / Demo.
class _SensorStatusBanner extends StatelessWidget {
  const _SensorStatusBanner({
    required this.demoMode,
    required this.hub,
    required this.busy,
    required this.onPair,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onOpenSensors,
    required this.onDemo,
    required this.onExitDemo,
  });

  final bool demoMode;
  final SensorHub? hub;
  final bool busy;
  final VoidCallback onPair;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;
  final VoidCallback onOpenSensors;
  final VoidCallback onDemo;
  final VoidCallback onExitDemo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final String title;
    final String subtitle;
    final Color color;
    final Color onColor;
    final IconData icon;
    final String actionLabel;
    final VoidCallback? action;
    final Key actionKey;

    if (demoMode) {
      color = cs.tertiaryContainer;
      onColor = cs.onTertiaryContainer;
      icon = Icons.science;
      title = 'Demo mode';
      subtitle = 'Synthetic force data — not your Progressor';
      actionLabel = 'Exit demo';
      action = onExitDemo;
      actionKey = const Key('live_exit_demo');
    } else {
      final p = hub?.progressor;
      final connected = hub?.isProgressorConnected ?? false;
      final paired = p != null;
      final hasId = p?.hasBleId ?? false;
      final err = hub?.lastError;

      if (connected) {
        color = cs.primaryContainer;
        onColor = cs.onPrimaryContainer;
        icon = Icons.sensors;
        title = 'Progressor connected — ready';
        subtitle = p?.name ?? 'Tindeq Progressor';
        actionLabel = 'Disconnect';
        action = onDisconnect;
        actionKey = const Key('live_disconnect');
      } else if (busy) {
        color = cs.secondaryContainer;
        onColor = cs.onSecondaryContainer;
        icon = Icons.bluetooth_searching;
        title = 'Connecting…';
        subtitle = 'Keep Progressor powered on and nearby';
        actionLabel = 'Sensors';
        action = onOpenSensors;
        actionKey = const Key('live_sensors_busy');
      } else if (!paired) {
        color = cs.errorContainer;
        onColor = cs.onErrorContainer;
        icon = Icons.sensors_off;
        title = 'No Progressor paired';
        subtitle = 'Pair your Tindeq Progressor to measure real force';
        actionLabel = 'Pair sensor';
        action = onPair;
        actionKey = const Key('live_pair');
      } else if (!hasId) {
        color = cs.errorContainer;
        onColor = cs.onErrorContainer;
        icon = Icons.radar;
        title = 'Progressor added — not scanned';
        subtitle = err ?? 'Scan to assign Bluetooth id, then Connect';
        actionLabel = 'Scan';
        action = onPair;
        actionKey = const Key('live_scan');
      } else {
        color = cs.errorContainer;
        onColor = cs.onErrorContainer;
        icon = Icons.bluetooth_disabled;
        title = 'Progressor not connected';
        subtitle = err ?? 'Reconnect to start measuring';
        actionLabel = 'Reconnect';
        action = onReconnect;
        actionKey = const Key('live_reconnect');
      }
    }

    return Material(
      key: const Key('live_sensor_status'),
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: onColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onColor.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: actionKey,
                  onPressed: busy ? null : action,
                  style: FilledButton.styleFrom(
                    backgroundColor: onColor.withValues(alpha: 0.15),
                    foregroundColor: onColor,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
            if (!demoMode) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('live_try_demo'),
                  onPressed: busy ? null : onDemo,
                  style: TextButton.styleFrom(
                    foregroundColor: onColor,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Try demo without hardware'),
                ),
              ),
            ],
          ],
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
