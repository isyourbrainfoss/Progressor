import 'dart:convert';
import 'dart:typed_data';

/// Tindeq Progressor BLE protocol (public API, tindeq.com/progressor_api).
///
/// Control point (write) and data point (notify) both use a TLV layout:
/// `[tag, length, value...]`, little endian.
abstract final class TindeqProtocol {
  static const String serviceUuid = '7e4e1701-1ea6-40c9-9dcc-13d34ffead57';
  static const String dataCharUuid = '7e4e1702-1ea6-40c9-9dcc-13d34ffead57';
  static const String ctrlCharUuid = '7e4e1703-1ea6-40c9-9dcc-13d34ffead57';

  // ---- commands (control point) ----
  static const int cmdTare = 0x64; // 100
  static const int cmdStartWeightMeas = 0x65; // 101
  static const int cmdStopWeightMeas = 0x66; // 102
  static const int cmdStartPeakRfdMeas = 0x67; // 103
  static const int cmdStartPeakRfdMeasSeries = 0x68; // 104
  static const int cmdAddCalibrationPoint = 0x69; // 105
  static const int cmdSaveCalibration = 0x6A; // 106
  static const int cmdGetAppVersion = 0x6B; // 107 — firmware version string
  static const int cmdGetErrorInfo = 0x6C; // 108
  static const int cmdClearErrorInfo = 0x6D; // 109
  static const int cmdEnterSleep = 0x6E; // 110 — power off
  static const int cmdGetBatteryVoltage = 0x6F; // 111 — uint32 mV

  // ---- responses (data point) ----
  static const int resCmdResponse = 0x00;
  static const int resWeightMeas = 0x01;
  static const int resRfdPeak = 0x02;
  static const int resRfdPeakSeries = 0x03;
  static const int resLowPowerWarning = 0x04;

  /// Bytes per weight record: float32 kg + uint32 µs timestamp.
  static const int weightRecordBytes = 8;

  /// Nominal sample rate of the Progressor 200 in weight-measurement mode.
  static const int sampleRateHz = 80;

  /// Approximate Li-ion state of charge from battery millivolts (linear
  /// 3.30 V → 0 %, 4.15 V → 100 %). Only a rough UI hint.
  static int batteryPercentFromMillivolts(int mv) {
    const empty = 3300;
    const full = 4150;
    final pct = ((mv - empty) * 100 / (full - empty)).round();
    return pct.clamp(0, 100);
  }

  /// Encode a weight notification the way the device sends it.
  static Uint8List encodeWeightPacket(List<TindeqWeightRecord> records) {
    final len = records.length * weightRecordBytes;
    final out = ByteData(2 + len);
    out.setUint8(0, resWeightMeas);
    out.setUint8(1, len);
    for (var i = 0; i < records.length; i++) {
      final o = 2 + i * weightRecordBytes;
      out.setFloat32(o, records[i].kg, Endian.little);
      out.setUint32(o + 4, records[i].timestampUs, Endian.little);
    }
    return out.buffer.asUint8List();
  }

  /// Encode a command-response notification (`tag 0`).
  static Uint8List encodeCmdResponse(List<int> value) {
    return Uint8List.fromList([resCmdResponse, value.length, ...value]);
  }

  static Uint8List encodeUint32Response(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    return encodeCmdResponse(b.buffer.asUint8List());
  }

  /// Parse one data-point notification.
  static TindeqNotification parse(List<int> data) {
    if (data.isEmpty) return const TindeqNotification.unknown(-1);
    final tag = data[0];
    switch (tag) {
      case resWeightMeas:
        return TindeqNotification.weight(_parseWeights(data));
      case resCmdResponse:
        return TindeqNotification.cmdResponse(_payload(data));
      case resLowPowerWarning:
        return const TindeqNotification.lowPower();
      default:
        return TindeqNotification.unknown(tag);
    }
  }

  static List<int> _payload(List<int> data) {
    if (data.length < 2) return const [];
    final len = data[1];
    final end = (2 + len).clamp(2, data.length);
    return data.sublist(2, end);
  }

  static List<TindeqWeightRecord> _parseWeights(List<int> data) {
    // Normal layout: [0x01, len, (f32, u32)*N]. Be lenient with a missing
    // length byte (1 + 8N bytes) which some third-party docs describe.
    int start;
    if (data.length >= 2 && (data.length - 2) % weightRecordBytes == 0) {
      start = 2;
    } else if ((data.length - 1) % weightRecordBytes == 0) {
      start = 1;
    } else {
      start = 2;
    }
    final bytes = Uint8List.fromList(data);
    final bd = ByteData.sublistView(bytes);
    final out = <TindeqWeightRecord>[];
    for (
      var i = start;
      i + weightRecordBytes <= bytes.length;
      i += weightRecordBytes
    ) {
      final kg = bd.getFloat32(i, Endian.little);
      final us = bd.getUint32(i + 4, Endian.little);
      if (kg.isNaN || kg.isInfinite || kg.abs() > 500) continue;
      out.add(TindeqWeightRecord(kg: kg, timestampUs: us));
    }
    return out;
  }

  /// Decode a command response payload as little-endian uint32 (battery mV).
  static int? payloadUint32(List<int> payload) {
    if (payload.length < 4) return null;
    final bd = ByteData.sublistView(Uint8List.fromList(payload.sublist(0, 4)));
    return bd.getUint32(0, Endian.little);
  }

  /// Decode a command response payload as ASCII/UTF-8 text (app version).
  static String payloadString(List<int> payload) {
    final trimmed = payload.takeWhile((b) => b != 0).toList();
    return utf8.decode(trimmed, allowMalformed: true).trim();
  }
}

class TindeqWeightRecord {
  const TindeqWeightRecord({required this.kg, required this.timestampUs});
  final double kg;
  final int timestampUs;
}

enum TindeqNotificationKind { weight, cmdResponse, lowPower, unknown }

class TindeqNotification {
  const TindeqNotification.weight(this.records)
    : kind = TindeqNotificationKind.weight,
      payload = const [],
      tag = TindeqProtocol.resWeightMeas;
  const TindeqNotification.cmdResponse(this.payload)
    : kind = TindeqNotificationKind.cmdResponse,
      records = const [],
      tag = TindeqProtocol.resCmdResponse;
  const TindeqNotification.lowPower()
    : kind = TindeqNotificationKind.lowPower,
      records = const [],
      payload = const [],
      tag = TindeqProtocol.resLowPowerWarning;
  const TindeqNotification.unknown(this.tag)
    : kind = TindeqNotificationKind.unknown,
      records = const [],
      payload = const [];

  final TindeqNotificationKind kind;
  final List<TindeqWeightRecord> records;
  final List<int> payload;
  final int tag;
}
