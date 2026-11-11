/// Maps device timestamps (µs since START_WEIGHT_MEAS) onto a monotonic
/// host-anchored millisecond timeline.
///
/// The Progressor batches several samples into one BLE notification, so
/// stamping each sample with the host receive time gives identical times for
/// the whole batch (staircase plots, broken RFD). Device timestamps are exact
/// but restart at 0 on every START command. This clock keeps device spacing
/// and re-anchors to host time whenever the device clock jumps backwards (a
/// restart) or drifts too far from the host clock (missed notifications).
class MonotonicSampleClock {
  MonotonicSampleClock({this.maxDriftMs = 1500});

  /// Re-anchor when device-derived time and host time disagree by this much.
  final int maxDriftMs;

  int? _anchorHostMs;
  int? _anchorDeviceUs;
  int? _lastDeviceUs;
  int _lastOutMs = -1;

  void reset() {
    _anchorHostMs = null;
    _anchorDeviceUs = null;
    _lastDeviceUs = null;
    _lastOutMs = -1;
  }

  /// Returns the timeline position (ms) for a sample received at [hostMs]
  /// with optional device timestamp [deviceUs].
  int timeFor({required int hostMs, int? deviceUs}) {
    int out;
    if (deviceUs == null) {
      out = hostMs;
    } else {
      final restarted = _lastDeviceUs != null && deviceUs < _lastDeviceUs!;
      if (_anchorHostMs == null || restarted) {
        _anchor(hostMs, deviceUs);
      }
      out = _anchorHostMs! + ((deviceUs - _anchorDeviceUs!) ~/ 1000);
      // Device clock should trail host receive time slightly; if it runs far
      // ahead or behind (packets lost / app paused) snap back to host time.
      if ((out - hostMs).abs() > maxDriftMs) {
        _anchor(hostMs, deviceUs);
        out = hostMs;
      }
      _lastDeviceUs = deviceUs;
    }
    if (out < _lastOutMs) out = _lastOutMs;
    _lastOutMs = out;
    return out;
  }

  void _anchor(int hostMs, int deviceUs) {
    // Anchor so this sample lands at hostMs but never before the last output.
    final base = hostMs < _lastOutMs ? _lastOutMs : hostMs;
    _anchorHostMs = base;
    _anchorDeviceUs = deviceUs;
  }
}
