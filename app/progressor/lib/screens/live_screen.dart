import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../live/protocol_session.dart';
import '../live/warmup_tour.dart';
import '../persistence/session_store.dart';
import '../sensors/sensor_hub.dart';
import '../widgets/pr_celebration.dart';
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
  MockReplayAdapter? _demoAdapter;
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
  WarmupTourController? _tour;
  Timer? _tickTimer;
  String _selectedHand = 'Right';
  double _userMaxKg = 40;
  DateTime? _lastPeakHaptic;
  bool _peakHighlight = false;

  /// Host clock base for plot times (never reset on startMeasurement).
  int? _hostTimeBaseMs;

  // Cached session UI (from ProtocolSession / tour)
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
    if (_demoMode && (_hub?.isProgressorConnected ?? false)) {
      unawaited(_exitDemoMode());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Progressor connected — left demo mode'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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

    // Host-monotonic times: independent of device startMeasurement resets so
    // the plot never compresses into a thin vertical strip.
    final hostNow = DateTime.now().millisecondsSinceEpoch;
    _hostTimeBaseMs ??= hostNow;
    final hostT = (hostNow - _hostTimeBaseMs!).clamp(0, 1 << 30);
    final timed = ForceSample(
      timeMs: hostT,
      forceKg: s.forceKg,
      rawTimestampUs: s.rawTimestampUs,
    );

    _liveSamples.add(timed);
    if (_liveSamples.length > _maxLivePoints) {
      _liveSamples.removeRange(0, _liveSamples.length - _maxLivePoints);
    }

    if (_isRecording) {
      final base = _sessionTimeBaseMs ??= hostT;
      final rebased = ForceSample(
        timeMs: (hostT - base).clamp(0, 1 << 30),
        forceKg: s.forceKg,
        rawTimestampUs: s.rawTimestampUs,
      );
      _sessionSamples.add(rebased);
      // Cap session buffer for long tours.
      if (_sessionSamples.length > 4000) {
        _sessionSamples.removeRange(0, _sessionSamples.length - 4000);
      }
      _session?.onSample(rebased);
      if (_peakForce == null || s.forceKg > _peakForce!) {
        _peakForce = s.forceKg;
        _peakHighlight = true;
        final nowH = DateTime.now();
        if (_lastPeakHaptic == null ||
            nowH.difference(_lastPeakHaptic!) >
                const Duration(milliseconds: 120)) {
          _lastPeakHaptic = nowH;
          HapticFeedback.mediumImpact();
        }
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (mounted) setState(() => _peakHighlight = false);
        });
      }
    }

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
    if (!mounted) return;
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
    if (!mounted) return;
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
        _liveSamples.clear();
        _hostTimeBaseMs = null;
      });
    }
  }

  Future<void> _enterDemoMode() async {
    final hub = _hub;
    if (hub?.isProgressorConnected == true && hub!.progressor != null) {
      await hub.disconnect(hub.progressor!.id);
    }
    await _demoAdapter?.dispose();
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
      await _demoAdapter?.dispose();
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
      // Demo: start the synthetic pull from rest so the recording captures a
      // whole rep instead of joining the loop mid-hold.
      if (_demoMode) _demoAdapter?.restart();
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }

    final now = DateTime.now();
    _session?.stop();
    _tour?.stop();
    _tickTimer?.cancel();

    WarmupTourController? tour;
    if (type == TestType.warmupTour) {
      tour = WarmupTourController();
      tour.start(now);
    }

    final protocolType = tour?.protocolType ?? type;
    final hand = tour != null ? tour.hand : _selectedHand;
    if (hand == 'Left' || hand == 'Right' || hand == 'Both') {
      _selectedHand = hand;
    }

    ProtocolSession? session;
    if (protocolType != TestType.warmupTour) {
      session = ProtocolSession(
        type: protocolType,
        userMaxKg: _userMaxKg,
        hand: _selectedHand,
      );
      session.start(now);
    }

    setState(() {
      _tour = tour;
      _session = session;
      _currentType = type;
      _isRecording = true;
      _recordStartTime = now;
      _sessionTimeBaseMs = null;
      _sessionSamples.clear();
      _peakForce = _currentForce;
      _applySessionUi(session, tour, now);
    });

    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_isRecording) {
        _tickTimer?.cancel();
        return;
      }
      final t = DateTime.now();
      final tourCtrl = _tour;
      if (tourCtrl != null && tourCtrl.isActive) {
        final advanced = tourCtrl.tick(t);
        if (advanced) {
          unawaited(_onTourStepChanged(t));
          return;
        }
      }
      _session?.tick(t);
      if (!mounted) return;
      setState(() {
        _applySessionUi(_session, _tour, t);
      });
    });

    final label = tour != null
        ? 'Warm-up tour · ${tour.current.hand} · ${tour.current.title}'
        : '${type.label} started';
    messenger?.showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 2)),
    );
  }

  void _applySessionUi(
    ProtocolSession? session,
    WarmupTourController? tour,
    DateTime now,
  ) {
    if (tour != null && (tour.isActive || tour.current.id == 'done')) {
      final step = tour.current;
      _phaseLabel = step.isPause
          ? 'PAUSE'
          : (session?.phaseLabel.isNotEmpty == true
              ? session!.phaseLabel
              : step.title);
      _instruction = step.instruction;
      if (session != null && !step.isPause) {
        _targetForce = session.targetForceKg;
        _matchPercent = session.matchPercent;
        _targetHistoryKg = List.of(session.targetHistoryKg);
        final c = session.countdownSeconds;
        final tourC = tour.countdownSeconds(now);
        // Prefer the shorter remaining cue.
        if (c != null && tourC != null) {
          _countdownSeconds = c < tourC ? c : tourC;
        } else {
          _countdownSeconds = tourC ?? c;
        }
      } else {
        _targetForce = null;
        _countdownSeconds = null;
        _matchPercent = null;
        _targetHistoryKg = const [];
      }
      if (step.hand == 'Left' || step.hand == 'Right' || step.hand == 'Both') {
        _selectedHand = step.hand;
      }
      return;
    }
    if (session != null) {
      _phaseLabel = session.phaseLabel;
      _instruction = session.instruction;
      _targetForce = session.targetForceKg;
      _countdownSeconds = session.countdownSeconds;
      _matchPercent = session.matchPercent;
      _targetHistoryKg = List.of(session.targetHistoryKg);
    }
  }

  Future<void> _onTourStepChanged(DateTime now) async {
    final tour = _tour;
    if (tour == null) return;
    final step = tour.current;

    // Stop previous protocol session when changing tour step.
    _session?.stop();
    _session = null;
    _sessionTimeBaseMs = null;
    // Keep force samples for one continuous tour log; optional soft re-base
    // only for chart clarity on timed work steps:
    if (!step.isPause && step.type != null) {
      // Don't clear whole tour history — chart can show full tour.
    }

    if (step.hand == 'Left' || step.hand == 'Right' || step.hand == 'Both') {
      _selectedHand = step.hand;
    }

    ProtocolSession? session;
    if (!step.isPause && step.type != null) {
      session = ProtocolSession(
        type: step.type!,
        userMaxKg: _userMaxKg,
        hand: _selectedHand,
      );
      session.start(now);
    }

    if (!mounted) return;
    setState(() {
      _session = session;
      _applySessionUi(session, tour, now);
    });

    if (mounted && step.hand != '—') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            step.hand == 'Left' || step.hand == 'Right'
                ? '→ Switch to ${step.hand.toUpperCase()} hand · ${step.title}'
                : step.title,
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }

  /// Pause steps and “done”: Continue. Timed steps: skip to next early.
  Future<void> _tourNext() async {
    final tour = _tour;
    if (tour == null) return;
    final now = DateTime.now();
    if (tour.current.id == 'done') {
      await _stopSession(save: true);
      return;
    }
    tour.advance(now);
    if (tour.current.id == 'done') {
      // Landed on terminal step — show it; user taps again or FINISH to save.
      _session?.stop();
      _session = null;
      if (mounted) {
        setState(() => _applySessionUi(null, tour, now));
      }
      return;
    }
    await _onTourStepChanged(now);
  }

  Future<void> _stopSession({bool save = true}) async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    final session = _session;
    final tour = _tour;
    final type = tour != null ? TestType.warmupTour : (session?.type ?? _currentType);
    final extras = <String, dynamic>{
      ...?session?.metricsExtras,
      if (tour != null) ...{
        'tourStepsCompleted': tour.stepIndex + 1,
        'tourStepCount': tour.stepCount,
        'tourLastStep': tour.current.id,
      },
    };
    final match = session?.matchPercent;

    _tickTimer?.cancel();
    _tickTimer = null;
    session?.stop();
    tour?.stop();

    final samples = List<ForceSample>.of(_sessionSamples);
    final start = _recordStartTime ?? DateTime.now();
    final end = DateTime.now();

    setState(() {
      _isRecording = false;
      _session = null;
      _tour = null;
      _sessionTimeBaseMs = null;
      _phaseLabel = '';
      _instruction = '';
      _targetForce = null;
      _countdownSeconds = null;
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

    final metrics = <String, dynamic>{
      ...computed.toJson(),
      ...extras,
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
      hand: _selectedHand,
      metrics: metrics,
    );

    SessionSaveResult? result;
    final store = mounted ? SessionStoreScope.maybeOf(context) : null;
    if (store != null) {
      result = await store.record(test);
    } else {
      await TestStorage().save(test);
    }

    final isNewPR = result?.isNewPr ?? false;
    final streak = result?.streak ?? 0;
    if (messenger != null && mounted) {
      final quality = match != null ? ' Match ${match.round()}%.' : '';
      if (isNewPR && peakKg != null) {
        await showPrCelebration(
          context,
          peakKg: peakKg,
          streak: streak,
          newlyUnlocked: result?.newlyUnlocked ?? const [],
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${type.label} • peak ${(peakKg ?? 0).toStringAsFixed(1)} kg. '
              'Streak $streak.$quality',
            ),
          ),
        );
      }
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
  // UI — idle = setup; recording = focus mode (minimal clutter)
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hub = _hub;
    final connected = _isConnected;
    final busy = _isConnecting;
    final target = _targetForce;
    final focus = _isRecording;
    final onTarget = target != null &&
        target > 0 &&
        _currentForce != null &&
        (_currentForce! - target).abs() < (target * 0.15).clamp(3, 15);

    final live = Scaffold(
      appBar: AppBar(
        title: Text(focus
            ? (_phaseLabel.isNotEmpty
                ? _phaseLabel
                : _currentType.label)
            : 'Live'),
        actions: [
          if (!focus) ...[
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: _showWarmupGuide,
              tooltip: 'Guide',
            ),
            IconButton(
              icon: const Icon(Icons.sensors),
              onPressed: _openSensors,
              tooltip: 'Sensors',
            ),
          ],
          if (focus)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Finish',
              onPressed: busy ? null : () => unawaited(_toggleRecord()),
            ),
        ],
      ),
      body: SafeArea(
        // Bottom nav sits outside this scaffold; only pad edges we own.
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: focus
                  ? _buildFocusBody(
                      context: context,
                      onTarget: onTarget,
                      target: target,
                    )
                  : _buildIdleBody(
                      context: context,
                      hub: hub,
                      busy: busy,
                      onTarget: onTarget,
                      target: target,
                    ),
            ),
            _buildControlBar(
              connected: connected,
              busy: busy,
              hub: hub,
              focus: focus,
            ),
          ],
        ),
      ),
    );

    final liveActive = TickerMode.valuesOf(context).enabled;
    return CallbackShortcuts(
      bindings: liveActive
          ? <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.space): () {
                if (!busy) unawaited(_toggleRecord());
              },
              const SingleActivator(LogicalKeyboardKey.keyT): () {
                unawaited(_activeAdapter?.tare() ?? Future.value());
              },
            }
          : const <ShortcutActivator, VoidCallback>{},
      child: live,
    );
  }

  /// Minimal mid-session UI: force + chart + one-line coaching.
  Widget _buildFocusBody({
    required BuildContext context,
    required bool onTarget,
    required double? target,
  }) {
    final tour = _tour;
    final hand = tour?.hand ?? _selectedHand;
    final showHand = hand == 'Left' || hand == 'Right' || hand == 'Both';

    return Column(
      children: [
        // Tour / hand banner
        if (tour != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: Colors.orangeAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          tour.progressLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.orangeAccent,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        if (showHand)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${hand.toUpperCase()} HAND',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (tour.stepIndex +
                                tour.progressFraction(DateTime.now())) /
                            tour.stepCount,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tour.current.title +
                          (tour.current.effortHint.isNotEmpty
                              ? ' · ${tour.current.effortHint}'
                              : ''),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (showHand)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${hand.toUpperCase()} HAND',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          label:
              'Force ${_currentForce?.toStringAsFixed(1) ?? 'zero'} kilograms',
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _currentForce != null
                  ? _currentForce!.toStringAsFixed(1)
                  : '—',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: 56,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: onTarget
                        ? Colors.greenAccent
                        : (_peakHighlight ? Colors.amberAccent : null),
                    height: 1.0,
                  ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('kg',
                style: TextStyle(fontSize: 16, color: Colors.white70)),
            if (target != null && target > 0) ...[
              const Text('  ·  ', style: TextStyle(color: Colors.white38)),
              Text(
                '→ ${target.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Colors.orangeAccent, fontSize: 16),
              ),
            ],
            if (_peakForce != null) ...[
              const Text('  ·  ', style: TextStyle(color: Colors.white38)),
              Text(
                'peak ${_peakForce!.toStringAsFixed(0)}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
            if (_countdownSeconds != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_countdownSeconds}s',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_matchPercent != null && _matchPercent! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Match ${_matchPercent!.toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LiveForceChart(
              samples: List.of(_chartSamples),
              targetForceKg: target != null && target > 0 ? target : null,
              targetHistoryKg:
                  _targetHistoryKg.isNotEmpty ? _targetHistoryKg : null,
              peakForceKg: _peakForce,
              height: 220,
              windowMs: 12000,
            ),
          ),
        ),
        if (_instruction.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(
              _instruction,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
      ],
    );
  }

  /// Setup UI when not in a session.
  Widget _buildIdleBody({
    required BuildContext context,
    required SensorHub? hub,
    required bool busy,
    required bool onTarget,
    required double? target,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _SensorStatusBanner(
              demoMode: _demoMode,
              hub: hub,
              busy: busy,
              compact: _isConnected && !_demoMode,
              onPair: _pairOrScan,
              onReconnect: _reconnect,
              onDisconnect: _disconnectHardware,
              onOpenSensors: _openSensors,
              onDemo: _enterDemoMode,
              onExitDemo: _exitDemoMode,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Semantics(
                  liveRegion: true,
                  label:
                      'Force ${_currentForce?.toStringAsFixed(1) ?? 'zero'} kilograms',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _currentForce != null
                          ? _currentForce!.toStringAsFixed(1)
                          : '—',
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(
                            fontSize: 56,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: onTarget
                                ? Colors.greenAccent
                                : (_peakHighlight
                                    ? Colors.amberAccent
                                    : null),
                            height: 1.0,
                          ),
                    ),
                  ),
                ),
                const Text('kg',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                if (_peakForce != null)
                  Text(
                    'peak ${_peakForce!.toStringAsFixed(1)}',
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 13),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LiveForceChart(
              samples: List.of(_chartSamples),
              targetForceKg: null,
              peakForceKg: _peakForce,
              height: 140,
              windowMs: 15000,
            ),
          ),
          const SizedBox(height: 8),
          ProtocolSelector(
            current: _currentType,
            onChanged: (t) => setState(() => _currentType = t),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              _currentType.description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          // Hand + max — compact single row
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                for (final h in ['L', 'R', 'Both'])
                  ChoiceChip(
                    label: Text(h, style: const TextStyle(fontSize: 11)),
                    selected: (_selectedHand == 'Left' && h == 'L') ||
                        (_selectedHand == 'Right' && h == 'R') ||
                        (_selectedHand == 'Both' && h == 'Both'),
                    onSelected: (_) => setState(() {
                      _selectedHand = h == 'L'
                          ? 'Left'
                          : h == 'R'
                              ? 'Right'
                              : 'Both';
                    }),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ActionChip(
                  label: Text('Max ${_userMaxKg.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11)),
                  onPressed: _editUserMax,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Quick start',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _quickChip(TestType.warmupTour, 'Tour 🔥'),
                _quickChip(TestType.followCurve, 'Curve'),
                _quickChip(TestType.holdRelease, 'Hold+Rel'),
                _quickChip(TestType.fingerDrag, 'Drag'),
                _quickChip(TestType.peakForce, 'Peak'),
                _quickChip(TestType.rfd, 'RFD'),
                _quickChip(TestType.repeaters, 'Reps 7:3'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom actions — always fully on-screen (Expanded + short labels).
  Widget _buildControlBar({
    required bool connected,
    required bool busy,
    required SensorHub? hub,
    required bool focus,
  }) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: focus
              ? Row(
                  children: [
                    Expanded(
                      child: _fitBarButton(
                        onPressed: (!connected || busy)
                            ? null
                            : () async {
                                final m = mounted
                                    ? ScaffoldMessenger.of(context)
                                    : null;
                                try {
                                  await _activeAdapter?.tare();
                                  m?.showSnackBar(const SnackBar(
                                    content: Text('Tared'),
                                    duration: Duration(milliseconds: 600),
                                  ));
                                } catch (e) {
                                  m?.showSnackBar(
                                      SnackBar(content: Text('Tare: $e')));
                                }
                              },
                        icon: Icons.balance,
                        label: 'TARE',
                        outlined: true,
                      ),
                    ),
                    if (_tour != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _fitBarButton(
                          onPressed:
                              busy ? null : () => unawaited(_tourNext()),
                          icon: _tour!.needsContinue ||
                                  _tour!.current.id == 'done'
                              ? Icons.arrow_forward
                              : Icons.skip_next,
                          label: _tour!.current.id == 'done'
                              ? 'FINISH TOUR'
                              : (_tour!.needsContinue
                                  ? 'CONTINUE'
                                  : 'NEXT'),
                          background: Colors.orangeAccent,
                          foreground: Colors.black,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      flex: _tour == null ? 2 : 1,
                      child: _fitBarButton(
                        onPressed:
                            busy ? null : () => unawaited(_toggleRecord()),
                        icon: Icons.stop,
                        label: _tour != null
                            ? 'END'
                            : (_currentType.isWarmup ? 'FINISH' : 'STOP'),
                        background: Colors.redAccent,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _demoMode
                          ? _fitBarButton(
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_exitDemoMode()),
                              icon: Icons.science,
                              label: 'Demo',
                              outlined: true,
                            )
                          : connected
                              ? _fitBarButton(
                                  onPressed: busy
                                      ? null
                                      : () =>
                                          unawaited(_disconnectHardware()),
                                  icon: Icons.link_off,
                                  label: 'Disc.',
                                  outlined: true,
                                )
                              : _fitBarButton(
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(
                                            (hub?.hasProgressor ?? false)
                                                ? _reconnect()
                                                : _pairOrScan(),
                                          ),
                                  icon: busy
                                      ? Icons.hourglass_empty
                                      : ((hub?.hasProgressor ?? false)
                                          ? Icons.bluetooth_searching
                                          : Icons.sensors),
                                  label: busy
                                      ? '…'
                                      : ((hub?.hasProgressor ?? false)
                                          ? 'Conn.'
                                          : 'Pair'),
                                  tonal: true,
                                ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _fitBarButton(
                        onPressed: busy
                            ? null
                            : () => unawaited(_toggleRecord()),
                        icon: Icons.play_arrow,
                        label: 'START',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _fitBarButton(
                        onPressed: (!connected || busy)
                            ? null
                            : () async {
                                final m = mounted
                                    ? ScaffoldMessenger.of(context)
                                    : null;
                                try {
                                  await _activeAdapter?.tare();
                                  m?.showSnackBar(const SnackBar(
                                    content: Text('Tared'),
                                    duration: Duration(milliseconds: 600),
                                  ));
                                } catch (e) {
                                  m?.showSnackBar(
                                      SnackBar(content: Text('Tare: $e')));
                                }
                              },
                        icon: Icons.balance,
                        label: 'Tare',
                        outlined: true,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Icon+label that scales down instead of overflowing on narrow phones.
  Widget _fitBarButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool outlined = false,
    bool tonal = false,
    Color? background,
    Color? foreground,
  }) {
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      backgroundColor: background,
      foregroundColor: foreground,
      visualDensity: VisualDensity.compact,
    );
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          visualDensity: VisualDensity.compact,
        ),
        child: child,
      );
    }
    if (tonal) {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: child,
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
    unawaited(_demoAdapter?.dispose() ?? Future.value());
    super.dispose();
  }
}

/// Connection status — compact when already connected.
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
    this.compact = false,
  });

  final bool demoMode;
  final SensorHub? hub;
  final bool busy;
  final bool compact;
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
      subtitle = 'Synthetic force';
      actionLabel = 'Exit';
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
        title = p?.name.isNotEmpty == true ? p!.name : 'Progressor live';
        subtitle = 'Connected';
        actionLabel = 'Disc.';
        action = onDisconnect;
        actionKey = const Key('live_disconnect');
      } else if (busy) {
        color = cs.secondaryContainer;
        onColor = cs.onSecondaryContainer;
        icon = Icons.bluetooth_searching;
        title = 'Connecting…';
        subtitle = 'Keep nearby';
        actionLabel = '…';
        action = onOpenSensors;
        actionKey = const Key('live_sensors_busy');
      } else if (!paired) {
        color = cs.errorContainer;
        onColor = cs.onErrorContainer;
        icon = Icons.sensors_off;
        title = 'No Progressor paired';
        subtitle = 'Pair to measure real force';
        actionLabel = 'Pair';
        action = onPair;
        actionKey = const Key('live_pair');
      } else if (!hasId) {
        color = cs.errorContainer;
        onColor = cs.onErrorContainer;
        icon = Icons.radar;
        title = 'Scan needed';
        subtitle = err ?? 'Assign Bluetooth id';
        actionLabel = 'Scan';
        action = onPair;
        actionKey = const Key('live_scan');
      } else {
        color = cs.errorContainer;
        onColor = cs.onErrorContainer;
        icon = Icons.bluetooth_disabled;
        title = 'Not connected';
        subtitle = err ?? 'Reconnect to measure';
        actionLabel = 'Conn.';
        action = onReconnect;
        actionKey = const Key('live_reconnect');
      }
    }

    // Compact one-line strip when already connected.
    if (compact && !demoMode) {
      return Material(
        key: const Key('live_sensor_status'),
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: onColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: actionKey,
                onPressed: busy ? null : action,
                style: TextButton.styleFrom(
                  foregroundColor: onColor,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
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
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onColor.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
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
            if (!demoMode &&
                (hub?.isProgressorConnected != true)) ...[
              const SizedBox(height: 4),
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
