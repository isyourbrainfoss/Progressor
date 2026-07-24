import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../live/protocol_session.dart';
import '../sensors/sensor_hub.dart';
import '../widgets/protocol_selector.dart';
import 'sensors_screen.dart';

/// Live measurement screen — real Progressor via [SensorHub], optional Demo.
///
/// Force is always shown while connected. START begins a [ProtocolSession]
/// (peak / RFD / repeaters / warmups / …) without blanking the kg readout or
/// auto-taring. Samples stream into a rolling chart buffer continuously.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  SensorAdapter? _demoAdapter;
  bool _demoMode = false;

  /// Rolling live buffer (always filled while samples arrive).
  final List<ForceSample> _liveSamples = [];

  /// Session buffer (only while a protocol session is active / recording).
  final List<ForceSample> _sessionSamples = [];

  bool _isRecording = false;
  double? _currentForce;
  double? _peakForce;
  TestType _currentType = TestType.peakForce;
  DateTime? _recordStartTime;
  int? _sessionTimeBaseMs; // first sample timeMs after session start

  StreamSubscription<SensorSample>? _sampleSub;
  SensorAdapter? _listeningAdapter;
  SensorHub? _hub;
  bool _hubListening = false;
  DateTime? _lastUiForceUpdate;
  bool _startingStream = false;

  ProtocolSession? _session;
  Timer? _tickTimer;
  String _selectedHand = 'Right';
  double _userMaxKg = 40;

  // Cached session UI (from ProtocolSession)
  String _phaseLabel = '';
  String _instruction = '';
  double? _targetForce;
  int? _countdownSeconds;
  double? _matchPercent;
  List<double> _targetHistoryKg = const [];

  static const int _maxLivePoints = 900;

  SensorAdapter? get _activeAdapter {
    if (_demoMode) return _demoAdapter;
    return _hub?.activeAdapter;
  }

  bool get _isConnected {
    if (_demoMode) return _demoAdapter != null;
    return _hub?.isProgressorConnected ?? false;
  }

  bool get _isConnecting =>
      !_demoMode && _hub?.progressorState == SensorConnectionState.connecting;

  /// Chart shows session samples while recording, else rolling live buffer.
  List<ForceSample> get _chartSamples =>
      _isRecording && _sessionSamples.isNotEmpty ? _sessionSamples : _liveSamples;

  @override
  void initState() {
    super.initState();
    unawaited(_loadUserMax());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSampleListener();
      unawaited(_ensureLiveStreaming());
    });
  }

  Future<void> _loadUserMax() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble('user_max_kg');
      if (stored != null && stored > 5) {
        _userMaxKg = stored;
      } else {
        final previous = await TestStorage().loadAll();
        if (previous.isNotEmpty) {
          final peak = previous
              .map((p) => p.peakForceKg ?? 0.0)
              .fold<double>(0, max);
          if (peak > 5) _userMaxKg = peak;
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
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
    unawaited(_ensureLiveStreaming());
    setState(() {});
  }

  void _syncSampleListener() {
    final adapter = _activeAdapter;
    if (identical(adapter, _listeningAdapter) && _sampleSub != null) return;
    _sampleSub?.cancel();
    _listeningAdapter = adapter;
    if (adapter == null) {
      _sampleSub = null;
      return;
    }

    _sampleSub = adapter.samples.listen(_onSample);
    unawaited(_ensureLiveStreaming());
  }

  void _onSample(SensorSample s) {
    if (!mounted) return;

    // Always keep a rolling live buffer for the plot (even when not recording).
    _liveSamples.add(s);
    if (_liveSamples.length > _maxLivePoints) {
      _liveSamples.removeRange(0, _liveSamples.length - _maxLivePoints);
    }

    if (_isRecording) {
      // Re-base times so the session chart starts near t=0.
      final base = _sessionTimeBaseMs ??= s.timeMs;
      final rebased = ForceSample(
        timeMs: (s.timeMs - base).clamp(0, 1 << 30),
        forceKg: s.forceKg,
        rawTimestampUs: s.rawTimestampUs,
      );
      _sessionSamples.add(rebased);
      _session?.onSample(rebased);
      if (_peakForce == null || s.forceKg > _peakForce!) {
        _peakForce = s.forceKg;
      }
    }

    // Throttle UI ~20 Hz; always update force value.
    final now = DateTime.now();
    if (_lastUiForceUpdate != null &&
        now.difference(_lastUiForceUpdate!) < const Duration(milliseconds: 50)) {
      _currentForce = s.forceKg;
      return;
    }
    _lastUiForceUpdate = now;
    setState(() {
      _currentForce = s.forceKg;
    });
  }

  Future<void> _ensureLiveStreaming() async {
    if (_demoMode || _startingStream) return;
    final ble = _activeAdapter is TindeqBleAdapter
        ? _activeAdapter as TindeqBleAdapter
        : null;
    if (ble == null || ble.isMeasuring) return;
    _startingStream = true;
    try {
      await ble.startMeasurement();
    } catch (_) {
    } finally {
      _startingStream = false;
    }
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
    if (hub == null) throw Exception('Sensor hub unavailable');
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
    await _ensureLiveStreaming();
  }

  // ---------------------------------------------------------------------------
  // Connection helpers
  // ---------------------------------------------------------------------------

  Future<void> _openSensors() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SensorsScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pairOrScan() async {
    final hub = _hub;
    if (hub == null) return;
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
    if (!p.hasBleId) await runProgressorScanFlow(context, hub);
    if (hub.progressor?.hasBleId == true) {
      await hub.connect(hub.progressor!.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _disconnectHardware() async {
    if (_isRecording) await _stopSession(save: false);
    final hub = _hub;
    final p = hub?.progressor;
    if (hub == null || p == null) return;
    await hub.disconnect(p.id);
    if (mounted) {
      setState(() {
        _currentForce = null;
      });
    }
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

  // ---------------------------------------------------------------------------
  // Protocol session
  // ---------------------------------------------------------------------------

  Future<void> _startSession(TestType type) async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    try {
      await _ensureHardwareReady();
      await _ensureLiveStreaming();
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }

    final now = DateTime.now();
    _session?.stop();
    _tickTimer?.cancel();

    final session = ProtocolSession(
      type: type,
      userMaxKg: _userMaxKg,
      hand: _selectedHand,
    );
    session.start(now);

    setState(() {
      _session = session;
      _currentType = type;
      _isRecording = true;
      _recordStartTime = now;
      _sessionTimeBaseMs = null;
      _sessionSamples.clear();
      // Do NOT clear _currentForce — keep last live reading visible.
      _peakForce = _currentForce;
      _phaseLabel = session.phaseLabel;
      _instruction = session.instruction;
      _targetForce = session.targetForceKg;
      _countdownSeconds = session.countdownSeconds;
      _matchPercent = session.matchPercent;
      _targetHistoryKg = List.of(session.targetHistoryKg);
    });

    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _session == null || !_session!.isActive) {
        _tickTimer?.cancel();
        return;
      }
      _session!.tick(DateTime.now());
      setState(() {
        _phaseLabel = _session!.phaseLabel;
        _instruction = _session!.instruction;
        _targetForce = _session!.targetForceKg;
        _countdownSeconds = _session!.countdownSeconds;
        _matchPercent = _session!.matchPercent;
        _targetHistoryKg = List.of(_session!.targetHistoryKg);
      });
    });

    messenger?.showSnackBar(
      SnackBar(
        content: Text('${type.label} started — $_phaseLabel'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _stopSession({bool save = true}) async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    final session = _session;
    final type = session?.type ?? _currentType;
    final extras = session?.metricsExtras ?? const <String, dynamic>{};
    final match = session?.matchPercent;

    _tickTimer?.cancel();
    _tickTimer = null;
    session?.stop();

    final samples = List<ForceSample>.of(_sessionSamples);
    final start = _recordStartTime ?? DateTime.now();
    final end = DateTime.now();

    setState(() {
      _isRecording = false;
      _session = null;
      _sessionTimeBaseMs = null;
      _phaseLabel = '';
      // Keep last instruction briefly? Clear for clean idle.
      _instruction = '';
      _targetForce = null;
      _countdownSeconds = null;
      // Keep match % visible for a moment after follow-curve.
      if (match == null) _matchPercent = null;
      _targetHistoryKg = const [];
      _recordStartTime = null;
    });

    if (!save || samples.isEmpty) return;

    final computed = computeMetrics(samples);
    final peakKg = computed.peakKg ?? _peakForce;
    if (peakKg != null && peakKg > _userMaxKg) {
      _userMaxKg = peakKg;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_max_kg', peakKg);
    }

    final previous = await TestStorage().loadAll();
    final prevMax = previous.isEmpty
        ? 0.0
        : previous.map((p) => p.peakForceKg ?? 0.0).reduce(max);
    final isNewPR = peakKg != null && peakKg > prevMax && !type.isWarmup;
    final streak = await _incrementStreakStub();

    final metrics = <String, dynamic>{
      ...computed.toJson(),
      ...extras,
      'isPR': isNewPR,
      'streakAtSave': streak,
      'source': _demoMode ? 'demo' : 'progressor',
      if (match != null) 'warmupMatchPercent': match.round(),
    };

    final notes = type.isWarmup
        ? 'Warm-up • ${type.label} • $_selectedHand'
        : (type == TestType.custom
            ? 'Free log'
            : '${type.label} • $_selectedHand');

    final test = PullTest(
      id: const Uuid().v4(),
      startTime: start,
      type: type,
      samples: samples,
      endTime: end,
      notes: notes,
      metrics: metrics,
    );
    await TestStorage().save(test);

    if (messenger != null && mounted) {
      final quality =
          match != null ? ' Match ${match.round()}%.' : '';
      final msg = isNewPR
          ? '🎉 NEW PR ${peakKg.toStringAsFixed(1)} kg! Streak $streak.$quality'
          : 'Saved ${type.label} • peak ${(peakKg ?? 0).toStringAsFixed(1)} kg. Streak $streak.$quality';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await _stopSession(save: true);
    } else {
      await _startSession(_currentType);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hub = _hub;
    final connected = _isConnected;
    final busy = _isConnecting;
    final target = _targetForce;
    final onTarget = target != null &&
        target > 0 &&
        _currentForce != null &&
        (_currentForce! - target).abs() < (target * 0.15).clamp(3, 15);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showWarmupGuide,
            tooltip: 'Warm-up Guide',
          ),
          IconButton(
            icon: const Icon(Icons.sensors),
            onPressed: _openSensors,
            tooltip: 'Sensors',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear plot',
            onPressed: () => setState(() {
              _liveSamples.clear();
              if (!_isRecording) {
                _sessionSamples.clear();
                _peakForce = null;
              }
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

                    // Big force
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
                                  color: onTarget ? Colors.greenAccent : null,
                                ),
                          ),
                          const Text('kg',
                              style: TextStyle(
                                  fontSize: 20, color: Colors.white70)),
                          if (target != null && target > 0)
                            Text(
                              'target ${target.toStringAsFixed(1)} kg'
                              '${_phaseLabel.isNotEmpty ? ' · $_phaseLabel' : ''}',
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
                          if (_countdownSeconds != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$_countdownSeconds s',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Live plot — always shows rolling data + target path
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LiveForceChart(
                        samples: List.of(_chartSamples),
                        targetForceKg:
                            target != null && target > 0 ? target : null,
                        targetHistoryKg: _isRecording &&
                                _targetHistoryKg.isNotEmpty
                            ? _targetHistoryKg
                            : null,
                        peakForceKg: _peakForce,
                        height: 180,
                        windowMs: 15000,
                      ),
                    ),

                    const SizedBox(height: 8),

                    ProtocolSelector(
                      current: _currentType,
                      onChanged: (t) {
                        if (_isRecording) return; // lock type mid-session
                        setState(() => _currentType = t);
                      },
                    ),

                    // Hand + estimated max (for % targets)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Hand ', style: TextStyle(fontSize: 12)),
                          for (final h in ['Left', 'Right', 'Both']) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: ChoiceChip(
                                label: Text(h, style: const TextStyle(fontSize: 12)),
                                selected: _selectedHand == h,
                                onSelected: _isRecording
                                    ? null
                                    : (_) =>
                                        setState(() => _selectedHand = h),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            'Max ${_userMaxKg.toStringAsFixed(0)} kg',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54),
                          ),
                          IconButton(
                            tooltip: 'Set estimated max (for % targets)',
                            icon: const Icon(Icons.edit, size: 16),
                            onPressed:
                                _isRecording ? null : _editUserMax,
                          ),
                        ],
                      ),
                    ),

                    // Session coaching panel
                    if (_isRecording || _instruction.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                Colors.orangeAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _currentType.isWarmup
                                      ? Icons.accessibility_new
                                      : Icons.fitness_center,
                                  color: Colors.orangeAccent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _currentType.label +
                                        (_phaseLabel.isNotEmpty
                                            ? ' · $_phaseLabel'
                                            : ''),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_instruction.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(_instruction,
                                  style: const TextStyle(fontSize: 14)),
                            ],
                            if (_matchPercent != null && _matchPercent! > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Match quality: ${_matchPercent!.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            if (_isRecording &&
                                (_currentType == TestType.followCurve ||
                                    _currentType ==
                                        TestType.holdRelease ||
                                    _currentType == TestType.repeaters ||
                                    _currentType == TestType.endurance))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => setState(() {
                                        _userMaxKg =
                                            (_userMaxKg - 5).clamp(15, 200);
                                        // Restart target scale mid-session is complex;
                                        // nudge current target display only.
                                        if (_targetForce != null) {
                                          _targetForce = (_targetForce! - 2)
                                              .clamp(3, 150);
                                        }
                                      }),
                                      child: const Text('- target'),
                                    ),
                                    const SizedBox(width: 6),
                                    OutlinedButton(
                                      onPressed: () => setState(() {
                                        _userMaxKg =
                                            (_userMaxKg + 5).clamp(15, 200);
                                        if (_targetForce != null) {
                                          _targetForce = (_targetForce! + 2)
                                              .clamp(3, 150);
                                        }
                                      }),
                                      child: const Text('+ target'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )
                    else ...[
                      // Protocol description when idle
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Text(
                          _currentType.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white60),
                        ),
                      ),
                      if (_currentType.isWarmup)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => unawaited(
                                    _startSession(_currentType)),
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
                      if (!_isRecording)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Quick warm-ups',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                children: [
                                  _quickChip(TestType.fingerDrag, 'Drag'),
                                  _quickChip(TestType.fingerCurl, 'Curls'),
                                  _quickChip(TestType.followCurve, 'Curve'),
                                  _quickChip(
                                      TestType.holdRelease, 'Hold+Rel'),
                                  _quickChip(
                                      TestType.warmupProgressive, 'Prog'),
                                  _quickChip(TestType.peakForce, 'Peak'),
                                  _quickChip(TestType.rfd, 'RFD'),
                                  _quickChip(TestType.repeaters, 'Reps'),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_demoMode)
                    FilledButton.tonalIcon(
                      onPressed:
                          busy ? null : () => unawaited(_exitDemoMode()),
                      icon: const Icon(Icons.science),
                      label: const Text('Exit Demo'),
                    )
                  else if (connected)
                    FilledButton.tonalIcon(
                      onPressed: busy
                          ? null
                          : () => unawaited(_disconnectHardware()),
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
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              (hub?.hasProgressor ?? false)
                                  ? Icons.bluetooth_searching
                                  : Icons.sensors,
                            ),
                      label: Text(
                        busy
                            ? '…'
                            : ((hub?.hasProgressor ?? false)
                                ? 'Connect'
                                : 'Pair'),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : () => unawaited(_toggleRecord()),
                    icon: Icon(
                        _isRecording ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      _isRecording
                          ? (_currentType.isWarmup ? 'FINISH' : 'STOP')
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

  Widget _quickChip(TestType type, String short) {
    return ActionChip(
      avatar: Icon(
        type.isWarmup ? Icons.accessibility_new : Icons.fitness_center,
        size: 16,
      ),
      label: Text(short),
      onPressed: () {
        setState(() => _currentType = type);
        unawaited(_startSession(type));
      },
    );
  }

  Future<void> _editUserMax() async {
    final controller =
        TextEditingController(text: _userMaxKg.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estimated max force (kg)'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            helperText:
                'Used for % targets (repeaters, warm-ups, follow curve).',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result > 5 && result < 300) {
      setState(() => _userMaxKg = result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_max_kg', result);
    }
  }

  Future<int> _incrementStreakStub() async {
    final prefs = await SharedPreferences.getInstance();
    int s = prefs.getInt('gamif_streak') ?? 0;
    s += 1;
    await prefs.setInt('gamif_streak', s);
    return s;
  }

  void _showWarmupGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finger training guide'),
        content: const SingleChildScrollView(
          child: Text(
            'Protocols\n'
            '• Peak — max single pull 3–5s\n'
            '• RFD — explosive pull; train rate of force\n'
            '• Repeaters — 7s on / 3s off @ ~40% max (CF density)\n'
            '• Endurance — sustained ~35% max\n'
            '• Follow Curve — match ramp/hold/release (control)\n'
            '• Hold+Release — isometric + slow eccentric (tendons)\n'
            '• Drag / Curls / Progressive — warm-up only, never max\n\n'
            'Tips\n'
            '• Set estimated Max for accurate % targets\n'
            '• Tare with empty Progressor before hard sets\n'
            '• Warm up thoroughly before Peak / RFD\n'
            '• Stop if sharp pain (not normal effort discomfort)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          TextButton(
            onPressed: () {
              launchUrl(Uri.parse(
                  'https://latticetraining.com/blog/how-to-manage-finger-strength-for-climbers'));
            },
            child: const Text('Lattice'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    if (_hubListening) {
      _hub?.removeListener(_onHubChanged);
      _hubListening = false;
    }
    _sampleSub?.cancel();
    unawaited(_demoAdapter?.disconnect() ?? Future.value());
    super.dispose();
  }
}

/// Flowlog-style readiness banner.
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

    late final String title;
    late final String subtitle;
    late final Color color;
    late final Color onColor;
    late final IconData icon;
    late final String actionLabel;
    late final VoidCallback? action;
    late final Key actionKey;

    if (demoMode) {
      color = cs.tertiaryContainer;
      onColor = cs.onTertiaryContainer;
      icon = Icons.science;
      title = 'Demo mode';
      subtitle = 'Synthetic force — not your Progressor';
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
        title = 'Progressor connected — live force';
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
