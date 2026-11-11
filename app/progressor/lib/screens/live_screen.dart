import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../live/live_modes.dart';
import '../live/protocol_session.dart';
import '../live/warmup_tour.dart';
import '../persistence/session_store.dart';
import '../sensors/sensor_hub.dart';
import '../widgets/pr_celebration.dart';
import 'sensors_screen.dart';

/// Live measurement screen — real Progressor via [SensorHub], or the
/// simulated demo device.
///
/// One screen, three things: the current force (huge), the peak (amber), and
/// a plot that fills the rest. A single mode button chooses what Start does
/// (free pull by default); hand, max and the less common protocols live in
/// the mode sheet. Start begins a [ProtocolSession] without blanking the
/// readout or auto-taring; samples stream into a rolling buffer continuously.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  /// Demo mode lives in [SensorHub] (simulated Progressor), so Sensors,
  /// Live and the DEMO dart-define all share one source of truth.
  bool get _demoMode => _hub?.isDemoActive ?? false;

  /// Rolling live buffer (always filled while samples arrive).
  final List<ForceSample> _liveSamples = [];

  /// Session buffer (only while a protocol session is active / recording).
  final List<ForceSample> _sessionSamples = [];

  bool _isRecording = false;
  double? _currentForce;
  double? _peakForce;
  TestType _currentType = TestType.custom;
  DateTime? _recordStartTime;
  int? _sessionTimeBaseMs; // first sample timeMs after session start

  StreamSubscription<SensorSample>? _sampleSub;
  SensorAdapter? _listeningAdapter;
  SensorHub? _hub;
  bool _hubListening = false;
  DateTime? _lastUiForceUpdate;
  bool _startingStream = false;

  /// Live has its own messenger so snackbars sit above the control bar
  /// instead of covering TARE / STOP (the shell's messenger put them over it).
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  ScaffoldMessengerState get _messenger =>
      _messengerKey.currentState ?? ScaffoldMessenger.of(context);

  ProtocolSession? _session;
  WarmupTourController? _tour;
  Timer? _tickTimer;
  String _selectedHand = 'Right';
  double _userMaxKg = 40;
  DateTime? _lastPeakHaptic;

  /// Stable y-axis for the plot (grows at once, shrinks only when idle).
  final LiveChartScale _scale = LiveChartScale();

  /// Visible plot window.
  static const int _chartWindowMs = 12000;

  /// Host clock base for plot times (never reset on startMeasurement).
  int? _hostTimeBaseMs;

  /// Keeps device sample spacing (batched BLE packets) on a monotonic timeline.
  final MonotonicSampleClock _sampleClock = MonotonicSampleClock();

  /// Target path with session-relative times (aligned with [_sessionSamples]).
  final List<ForceSample> _targetTrace = [];

  // Cached session UI (from ProtocolSession / tour)
  String _phaseLabel = '';
  String _instruction = '';
  double? _targetForce;
  int? _countdownSeconds;
  double? _matchPercent;

  /// Rolling live buffer length (ms) — a bit more than the widest chart window.
  static const int _liveBufferMs = 20000;

  /// Session buffer cap: 45 min at 80 Hz. (Was 4000 samples ≈ 50 s, which
  /// silently dropped the start of repeaters / warm-up tours on save.)
  static const int _maxSessionSamples = 80 * 60 * 45;

  SensorAdapter? get _activeAdapter => _hub?.activeAdapter;

  bool get _isConnected => _hub?.hasLiveSource ?? false;

  bool get _isConnecting =>
      (_hub?.isDemoConnecting ?? false) ||
      (!_demoMode && _hub?.progressorState == SensorConnectionState.connecting);

  /// Chart shows session samples while recording (even before the first
  /// one arrives, so the previous pull cannot leak into the new session's
  /// y-scale), else the rolling live buffer.
  List<ForceSample> get _chartSamples =>
      _isRecording ? _sessionSamples : _liveSamples;

  /// Tail of [src] covering the last [windowMs] (cheap; avoids copying the
  /// whole session buffer on every frame).
  static List<ForceSample> _windowed(List<ForceSample> src, int windowMs) {
    if (src.isEmpty) return const [];
    final from = src.last.timeMs - windowMs - 250;
    var i = src.length - 1;
    while (i > 0 && src[i - 1].timeMs >= from) {
      i--;
    }
    return src.sublist(i);
  }

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

  static const String _modePrefKey = 'live_mode';

  Future<void> _loadUserMax() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(_modePrefKey);
      if (mode != null) {
        for (final m in kLiveModes) {
          if (m.type.name == mode) _currentType = m.type;
        }
      }
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
    _sampleClock.reset();
    if (adapter == null) {
      _sampleSub = null;
      return;
    }

    _sampleSub = adapter.samples.listen(_onSample);
    unawaited(_ensureLiveStreaming());
  }

  void _onSample(SensorSample s) {
    if (!mounted) return;

    // Monotonic host-anchored times that keep the device's 12.5 ms sample
    // spacing (a BLE notification carries several samples; stamping them all
    // with the arrival time made staircase plots and bogus RFD). Independent
    // of startMeasurement resets so the plot never compresses.
    final hostNow = DateTime.now().millisecondsSinceEpoch;
    _hostTimeBaseMs ??= hostNow;
    final hostRel = (hostNow - _hostTimeBaseMs!).clamp(0, 1 << 30);
    final hostT = _sampleClock.timeFor(
      hostMs: hostRel,
      deviceUs: s.rawTimestampUs,
    );
    final timed = ForceSample(
      timeMs: hostT,
      forceKg: s.forceKg,
      rawTimestampUs: s.rawTimestampUs,
    );

    _liveSamples.add(timed);
    if (_liveSamples.length > 64 &&
        _liveSamples.first.timeMs < hostT - _liveBufferMs) {
      final cut = _liveSamples.indexWhere(
        (e) => e.timeMs >= hostT - _liveBufferMs,
      );
      if (cut > 0) _liveSamples.removeRange(0, cut);
    }

    if (_isRecording) {
      final base = _sessionTimeBaseMs ??= hostT;
      final rebased = ForceSample(
        timeMs: (hostT - base).clamp(0, 1 << 30),
        forceKg: s.forceKg,
        rawTimestampUs: s.rawTimestampUs,
      );
      _sessionSamples.add(rebased);
      // Cap session buffer for very long tours.
      if (_sessionSamples.length > _maxSessionSamples) {
        _sessionSamples.removeRange(
          0,
          _sessionSamples.length - _maxSessionSamples,
        );
      }
      _session?.onSample(rebased);
    }

    // Peak is tracked all the time (since connect / last reset / Start), so
    // a quick pull without recording still shows what you managed.
    if (_peakForce == null || s.forceKg > _peakForce!) {
      final wasSet = _peakForce != null;
      _peakForce = s.forceKg;
      final nowH = DateTime.now();
      if (_isRecording &&
          wasSet &&
          s.forceKg > 2 &&
          (_lastPeakHaptic == null ||
              nowH.difference(_lastPeakHaptic!) >
                  const Duration(milliseconds: 400))) {
        _lastPeakHaptic = nowH;
        HapticFeedback.selectionClick();
      }
    }

    // ~25 fps is plenty for a readable plot and keeps rebuilds cheap.
    final now = DateTime.now();
    if (_lastUiForceUpdate != null &&
        now.difference(_lastUiForceUpdate!) <
            const Duration(milliseconds: 40)) {
      _currentForce = s.forceKg;
      return;
    }
    _lastUiForceUpdate = now;
    setState(() {
      _currentForce = s.forceKg;
    });
  }

  Future<void> _ensureLiveStreaming() async {
    if (_startingStream) return;
    final ble = _hub?.activeProgressor;
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
      _syncSampleListener();
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SensorsScreen()));
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
        _peakForce = null;
        _scale.reset();
        _liveSamples.clear();
        _hostTimeBaseMs = null;
      });
    }
  }

  Future<void> _enterDemoMode() async {
    final hub = _hub;
    if (hub == null) return;
    try {
      await hub.startDemo();
      _syncSampleListener();
    } catch (e) {
      if (mounted) {
        _messenger.showSnackBar(SnackBar(content: Text('Demo failed: $e')));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _exitDemoMode() async {
    if (!_demoMode) return;
    if (_isRecording) await _stopSession(save: false);
    await _hub?.stopDemo();
    if (!mounted) return;
    setState(() {
      _currentForce = null;
      _peakForce = null;
      _scale.reset();
      _liveSamples.clear();
    });
    _syncSampleListener();
  }

  /// In demo mode, tell the virtual climber what the coach is asking for.
  void _guideDemo() {
    final demo = _hub?.demoAdapter;
    if (demo == null) return;
    if (!_isRecording) {
      demo.guide(recording: false);
      return;
    }
    final tour = _tour;
    final pause = tour != null && tour.current.isPause;
    demo.guide(
      recording: true,
      type: pause ? null : (_session?.type ?? _currentType),
      phase: pause ? 'PAUSE' : (_session?.phaseLabel ?? _phaseLabel),
      targetKg: _targetForce,
    );
  }

  /// Append the current target to the time-aligned target trace.
  void _recordTargetPoint(DateTime now) {
    final base = _sessionTimeBaseMs;
    final hostBase = _hostTimeBaseMs;
    if (base == null || hostBase == null) return;
    final t = now.millisecondsSinceEpoch - hostBase - base;
    if (t < 0) return;
    _targetTrace.add(ForceSample(timeMs: t, forceKg: _targetForce ?? 0));
    if (_targetTrace.length > 30000) _targetTrace.removeRange(0, 10000);
  }

  // ---------------------------------------------------------------------------
  // Protocol session
  // ---------------------------------------------------------------------------

  Future<void> _startSession(TestType type) async {
    final messenger = mounted ? _messenger : null;
    // Nothing else may start while a session is running (e.g. a stray
    // Space press from the keyboard).
    if (_isRecording) return;
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
      _targetTrace.clear();
      _peakForce = null;
      _scale.reset();
      _applySessionUi(session, tour, now);
    });
    _guideDemo();

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
        _recordTargetPoint(t);
      });
      _guideDemo();
    });
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
    }
  }

  Future<void> _onTourStepChanged(DateTime now) async {
    final tour = _tour;
    if (tour == null) return;
    final step = tour.current;

    // Stop previous protocol session when changing tour step.
    _session?.stop();
    _session = null;
    // Keep ONE time base for the whole tour. Resetting it here restarted
    // sample times at 0 on every step, so the saved tour (and the live plot)
    // had overlapping, non-monotonic timestamps.

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
      _messenger.showSnackBar(
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
    final messenger = mounted ? _messenger : null;
    final session = _session;
    final tour = _tour;
    final type = tour != null
        ? TestType.warmupTour
        : (session?.type ?? _currentType);
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
      _targetTrace.clear();
      _recordStartTime = null;
    });
    _guideDemo();

    if (!save || samples.isEmpty) return;

    final computed = computeMetrics(samples);
    final peakKg = computed.peakKg ?? _peakForce;
    // Simulated pulls must not move the user's real estimated max.
    if (!_demoMode && peakKg != null && peakKg > _userMaxKg) {
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
      notes: _demoMode ? 'DEMO • $notes' : notes,
      deviceName: (_hub?.activeProgressor)?.deviceName,
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
        final title = liveModeFor(type).title;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Saved $title · peak ${(peakKg ?? 0).toStringAsFixed(1)} kg.'
              '$quality'
              '${_demoMode ? ' Demo sessions do not count for records.' : ''}'
              '${progressorStorageIsPersistent ? '' : ' Not saved to disk: storage is unavailable.'}',
            ),
            duration: const Duration(seconds: 3),
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
  // Small actions
  // ---------------------------------------------------------------------------

  Future<void> _tare() async {
    final m = mounted ? _messenger : null;
    try {
      await _activeAdapter?.tare();
      // Old readings were relative to the previous zero.
      if (!_isRecording) _peakForce = null;
      m?.hideCurrentSnackBar();
      m?.showSnackBar(
        const SnackBar(
          content: Text('Zeroed'),
          duration: Duration(milliseconds: 900),
        ),
      );
    } catch (e) {
      m?.showSnackBar(SnackBar(content: Text('Tare failed: $e')));
    }
    if (mounted) setState(() {});
  }

  void _resetPeak() {
    if (_isRecording) return;
    setState(() {
      _peakForce = null;
      _scale.reset();
    });
  }

  Future<void> _pickMode() async {
    final picked = await showLiveModeSheet(
      context,
      current: _currentType,
      hand: _selectedHand,
      onHandChanged: (h) => setState(() => _selectedHand = h),
      userMaxKg: _userMaxKg,
      onEditMax: () => unawaited(_editUserMax()),
    );
    if (picked == null || !mounted) return;
    setState(() => _currentType = picked);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modePrefKey, picked.name);
    } catch (_) {}
  }

  Future<void> _editUserMax() async {
    final controller = TextEditingController(
      text: _userMaxKg.toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your max (kg)'),
        content: TextField(
          key: const Key('max_field'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            helperText: 'Your best max pull. Guided targets are a % of this.',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result > 5 && result < 300) {
      setState(() => _userMaxKg = result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_max_kg', result);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final connected = _isConnected;
    final busy = _isConnecting;
    // Max / explosive pulls have no real target: the protocol's "soft
    // target" is just the running peak, which the peak line already shows.
    final hasTarget =
        _currentType != TestType.peakForce && _currentType != TestType.rfd;
    final target = hasTarget && _targetForce != null && _targetForce! > 0
        ? _targetForce
        : null;
    final onTarget =
        target != null &&
        _currentForce != null &&
        (_currentForce! - target).abs() <= defaultTargetToleranceKg(target);

    final Widget body;
    if (!connected) {
      body = busy
          ? const _ConnectingPanel()
          : _ConnectPanel(
              hasProgressor: _hub?.hasProgressor ?? false,
              error: _hub?.lastError,
              onConnect: () => unawaited(
                (_hub?.hasProgressor ?? false) ? _reconnect() : _pairOrScan(),
              ),
              onDemo: () => unawaited(_enterDemoMode()),
            );
    } else {
      body = _buildLive(context, target: target, onTarget: onTarget);
    }

    final live = ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        body: SafeArea(
          // Bottom nav sits outside this scaffold; only pad edges we own.
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(context, connected: connected, busy: busy),
              Expanded(child: body),
            ],
          ),
        ),
        bottomNavigationBar: connected ? _buildControlBar(busy: busy) : null,
      ),
    );

    final liveActive = TickerMode.valuesOf(context).enabled;
    return CallbackShortcuts(
      bindings: liveActive && connected
          ? <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.space): () {
                if (!busy) unawaited(_toggleRecord());
              },
              const SingleActivator(LogicalKeyboardKey.keyT): () {
                unawaited(_tare());
              },
              const SingleActivator(LogicalKeyboardKey.keyR): _resetPeak,
            }
          : const <ShortcutActivator, VoidCallback>{},
      child: live,
    );
  }

  /// Device chip on the left, mode button on the right. Nothing else.
  Widget _buildTopBar(
    BuildContext context, {
    required bool connected,
    required bool busy,
  }) {
    final mode = liveModeFor(_currentType);
    final Widget left;
    if (_isRecording) {
      left = _RecordingChip(
        key: const Key('live_rec'),
        elapsed: DateTime.now().difference(_recordStartTime ?? DateTime.now()),
      );
    } else if (connected) {
      left = _DeviceChip(
        demo: _demoMode,
        name: _demoMode
            ? 'Simulated'
            : ((_hub?.progressor?.name.isNotEmpty ?? false)
                  ? _hub!.progressor!.name
                  : 'Progressor'),
        onDetails: () => unawaited(_openSensors()),
        onDisconnect: () =>
            unawaited(_demoMode ? _exitDemoMode() : _disconnectHardware()),
      );
    } else {
      left = Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text('Live', style: Theme.of(context).textTheme.titleLarge),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: left),
            ),
            const SizedBox(width: 8),
            if (connected)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _ModeButton(
                    key: const Key('live_mode'),
                    icon: mode.icon,
                    label: mode.title,
                    onPressed: _isRecording || busy
                        ? null
                        : () => unawaited(_pickMode()),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Sensors',
                icon: const Icon(Icons.sensors),
                onPressed: () => unawaited(_openSensors()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLive(
    BuildContext context, {
    required double? target,
    required bool onTarget,
  }) {
    final samples = _windowed(_chartSamples, _chartWindowMs);
    var visibleMax = 0.0;
    for (final s in samples) {
      if (s.forceKg > visibleMax) visibleMax = s.forceKg;
    }
    final trace = _targetTrace.any((e) => e.forceKg > 0)
        ? _windowed(_targetTrace, _chartWindowMs)
        : null;
    for (final s in trace ?? const <ForceSample>[]) {
      if (s.forceKg > visibleMax) visibleMax = s.forceKg;
    }
    final needed = [
      visibleMax,
      _peakForce ?? 0.0,
      if (target != null) target + defaultTargetToleranceKg(target),
    ].reduce(max);
    final top = _scale.update(needed, allowShrink: !_isRecording);

    final readout = _ForceReadout(
      forceKg: _currentForce,
      peakKg: _peakForce,
      onTarget: onTarget,
      onResetPeak: _isRecording ? null : _resetPeak,
    );
    final coach = _buildCoach(context, target: target);
    final chart = LiveForceChart(
      key: const Key('live_chart'),
      samples: samples,
      targetForceKg: target,
      // Follow-the-curve draws its moving target as a path instead.
      targetSamples: _currentType == TestType.followCurve ? trace : null,
      peakForceKg: _peakForce,
      maxKg: top,
      windowMs: _chartWindowMs,
      height: double.infinity,
      emptyHint: 'Waiting for force…',
      lineColor: onTarget ? const Color(0xFF4ADE80) : null,
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 840) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [readout, const SizedBox(height: 16), coach],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: chart),
              ],
            ),
          );
        }
        return Column(
          children: [
            const SizedBox(height: 4),
            readout,
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: coach,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: chart,
              ),
            ),
          ],
        );
      },
    );
  }

  /// One strip that says what to do now. Idle: what Start will do.
  Widget _buildCoach(BuildContext context, {required double? target}) {
    final mode = liveModeFor(_currentType);
    if (!_isRecording) {
      final text = _demoMode
          ? '${mode.summary} In the demo, a virtual climber pulls for you.'
          : mode.summary;
      return Text(
        text,
        key: const Key('live_hint'),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: Colors.white60),
      );
    }

    final tour = _tour;
    final free = _currentType == TestType.custom && tour == null;
    final rawPhase = _phaseLabel.isEmpty ? 'GO' : _phaseLabel;
    final phase = free ? 'RECORDING' : rawPhase;
    final color = _phaseColor(rawPhase);
    final hand = tour?.hand ?? _selectedHand;
    final handText = !free && (hand == 'Left' || hand == 'Right')
        ? '${hand.toUpperCase()} HAND'
        : null;
    final sub = [
      if (tour != null) tour.progressLabel,
      ?handText,
      if (target != null) 'target ${target.toStringAsFixed(0)} kg',
      if (_matchPercent != null && _matchPercent! > 0)
        'match ${_matchPercent!.toStringAsFixed(0)} %',
    ].join(' · ');
    final instruction = free
        ? 'Pull whenever you like. Stop saves the session.'
        : plainCoachInstruction(_instruction, rawPhase);

    return Container(
      key: const Key('live_coach'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  phase,
                  key: const Key('live_phase'),
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (_countdownSeconds != null)
                Text(
                  '${_countdownSeconds}s',
                  key: const Key('live_countdown'),
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (instruction.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                instruction,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white60),
              ),
            ),
        ],
      ),
    );
  }

  /// Bottom actions: Tare + one big Start / Stop (+ Next during a tour).
  Widget _buildControlBar({required bool busy}) {
    final tour = _tour;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: _barButton(
                  key: const Key('live_tare'),
                  onPressed: busy ? null : () => unawaited(_tare()),
                  icon: Icons.balance,
                  label: 'Tare',
                  outlined: true,
                ),
              ),
              if (_isRecording && tour != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _barButton(
                    key: const Key('live_next'),
                    onPressed: busy ? null : () => unawaited(_tourNext()),
                    icon: Icons.skip_next,
                    label: tour.current.id == 'done'
                        ? 'Finish'
                        : (tour.needsContinue ? 'Continue' : 'Next'),
                    outlined: true,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _isRecording
                    ? _barButton(
                        key: const Key('live_stop'),
                        onPressed: busy
                            ? null
                            : () => unawaited(_toggleRecord()),
                        icon: Icons.stop_rounded,
                        label: 'Stop',
                        background: const Color(0xFFE5484D),
                      )
                    : _barButton(
                        key: const Key('live_start'),
                        onPressed: busy
                            ? null
                            : () => unawaited(_toggleRecord()),
                        icon: Icons.play_arrow_rounded,
                        label: 'Start',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barButton({
    required Key key,
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool outlined = false,
    Color? background,
  }) {
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    const size = Size.fromHeight(56);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    if (outlined) {
      return OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(minimumSize: size, shape: shape),
        child: child,
      );
    }
    return FilledButton(
      key: key,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: size,
        shape: shape,
        backgroundColor: background,
        foregroundColor: Colors.white,
      ),
      child: child,
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
    super.dispose();
  }
}

Color _phaseColor(String phase) => switch (phase) {
  'REST' || 'PAUSE' || 'LOWER' => const Color(0xFF7DD3FC),
  'DONE' => const Color(0xFF4ADE80),
  'READY' => const Color(0xFFFFC94D),
  _ => const Color(0xFFFF8A5B),
};

/// Current force (huge) and peak (amber). The two numbers that matter.
class _ForceReadout extends StatelessWidget {
  const _ForceReadout({
    required this.forceKg,
    required this.peakKg,
    required this.onTarget,
    required this.onResetPeak,
  });

  final double? forceKg;
  final double? peakKg;
  final bool onTarget;
  final VoidCallback? onResetPeak;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final numberHeight = (h * 0.13).clamp(64.0, 132.0);
    final f = forceKg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Force ${f?.toStringAsFixed(1) ?? 'none'} kilograms',
          child: SizedBox(
            height: numberHeight,
            child: FittedBox(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    f != null ? _fmtKg(f) : '—',
                    key: const Key('live_force'),
                    style: TextStyle(
                      fontSize: 120,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: onTarget ? const Color(0xFF4ADE80) : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'kg',
                    style: TextStyle(fontSize: 36, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Material(
          color: const Color(0xFFFFC94D).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            key: const Key('live_peak'),
            borderRadius: BorderRadius.circular(22),
            onTap: onResetPeak,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'PEAK',
                    style: TextStyle(
                      color: Color(0xFFFFC94D),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    peakKg != null ? '${_fmtKg(peakKg!)} kg' : '—',
                    key: const Key('live_peak_value'),
                    style: const TextStyle(
                      color: Color(0xFFFFC94D),
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (onResetPeak != null && peakKg != null) ...[
                    const SizedBox(width: 8),
                    const Tooltip(
                      message: 'Reset peak',
                      child: Icon(
                        Icons.refresh,
                        size: 18,
                        color: Color(0xFFFFC94D),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mode button: what Start will do. Opens the mode sheet.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }
}

/// Which gauge is live. Tap for device details or to disconnect.
class _DeviceChip extends StatelessWidget {
  const _DeviceChip({
    required this.demo,
    required this.name,
    required this.onDetails,
    required this.onDisconnect,
  });

  final bool demo;
  final String name;
  final VoidCallback onDetails;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dot = demo ? cs.tertiary : const Color(0xFF4ADE80);
    return PopupMenuButton<String>(
      key: const Key('live_device'),
      tooltip: 'Device',
      position: PopupMenuPosition.under,
      onSelected: (v) => v == 'details' ? onDetails() : onDisconnect(),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'details',
          child: ListTile(
            leading: Icon(Icons.sensors),
            title: Text('Device details'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          key: Key(demo ? 'live_exit_demo' : 'live_disconnect'),
          value: 'disconnect',
          child: ListTile(
            leading: const Icon(Icons.link_off),
            title: Text(demo ? 'Leave demo' : 'Disconnect'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (demo) ...[const SizedBox(width: 8), const _DemoBadge()],
          ],
        ),
      ),
    );
  }
}

class _RecordingChip extends StatelessWidget {
  const _RecordingChip({super.key, required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final s = elapsed.inSeconds;
    final t = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 10, color: Color(0xFFE5484D)),
          const SizedBox(width: 8),
          Text(
            'REC $t',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the readout when no gauge is live.
class _ConnectPanel extends StatelessWidget {
  const _ConnectPanel({
    required this.hasProgressor,
    required this.error,
    required this.onConnect,
    required this.onDemo,
  });

  final bool hasProgressor;
  final String? error;
  final VoidCallback onConnect;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('live_sensor_status'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.sensors, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                hasProgressor
                    ? 'Progressor not connected'
                    : 'No gauge connected',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Switch on your Tindeq Progressor and keep it close.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              if (error != null && error!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  key: const Key('live_error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: Key(hasProgressor ? 'live_reconnect' : 'live_pair'),
                onPressed: onConnect,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(hasProgressor ? 'Reconnect' : 'Connect Progressor'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('live_try_demo'),
                onPressed: onDemo,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Try the demo'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'No gauge needed: a simulated climber pulls for you, so you '
                'can see how it works. Demo sessions never count as records.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectingPanel extends StatelessWidget {
  const _ConnectingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('live_connecting'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Connecting…', style: TextStyle(fontSize: 18)),
          SizedBox(height: 4),
          Text(
            'Keep the Progressor close.',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

/// Small "DEMO" pill so simulated data is never mistaken for a real gauge.
class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('demo_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.tertiary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'DEMO',
        style: TextStyle(
          color: cs.onTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// One-decimal kg readout without a "-0.0" flicker around zero.
String _fmtKg(double kg) {
  final t = kg.toStringAsFixed(1);
  return t == '-0.0' ? '0.0' : t;
}
