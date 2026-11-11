import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:progressor_sensors/progressor_sensors.dart';

Uint8List _weightPacket(List<(double, int)> recs, {bool withLen = true}) {
  final b = BytesBuilder();
  b.addByte(0x01);
  if (withLen) b.addByte(recs.length * 8);
  for (final (kg, us) in recs) {
    final bd = ByteData(8)
      ..setFloat32(0, kg, Endian.little)
      ..setUint32(4, us, Endian.little);
    b.add(bd.buffer.asUint8List());
  }
  return b.toBytes();
}

void main() {
  test('command codes match the public Tindeq API', () {
    expect(TindeqProtocol.cmdTare, 0x64);
    expect(TindeqProtocol.cmdStartWeightMeas, 0x65);
    expect(TindeqProtocol.cmdStopWeightMeas, 0x66);
    expect(TindeqProtocol.cmdGetAppVersion, 0x6B);
    expect(TindeqProtocol.cmdEnterSleep, 0x6E);
    expect(TindeqProtocol.cmdGetBatteryVoltage, 0x6F);
    expect(TindeqProtocol.serviceUuid, '7e4e1701-1ea6-40c9-9dcc-13d34ffead57');
    expect(TindeqProtocol.dataCharUuid, startsWith('7e4e1702'));
    expect(TindeqProtocol.ctrlCharUuid, startsWith('7e4e1703'));
  });

  test('parses weight notification [0x01, len, (f32,u32)*N] little endian', () {
    final n = TindeqProtocol.parse(
      _weightPacket([(1.5, 1000), (22.25, 13500), (-0.5, 26000)]),
    );
    expect(n.kind, TindeqNotificationKind.weight);
    expect(n.records, hasLength(3));
    expect(n.records[1].kg, closeTo(22.25, 1e-6));
    expect(n.records[1].timestampUs, 13500);
    expect(n.records[2].kg, closeTo(-0.5, 1e-6));
  });

  test('tolerates a weight packet without the length byte', () {
    final n = TindeqProtocol.parse(
      _weightPacket([(10, 0), (11, 12500)], withLen: false),
    );
    expect(n.records.map((r) => r.kg), [10, 11]);
  });

  test('drops NaN / absurd floats', () {
    final n = TindeqProtocol.parse(
      _weightPacket([(double.nan, 0), (9999, 1), (5, 2)]),
    );
    expect(n.records, hasLength(1));
    expect(n.records.single.kg, 5);
  });

  test('encode/parse round trip', () {
    final bytes = TindeqProtocol.encodeWeightPacket(const [
      TindeqWeightRecord(kg: 3.25, timestampUs: 7),
      TindeqWeightRecord(kg: 4.5, timestampUs: 12507),
    ]);
    expect(bytes[0], 0x01);
    expect(bytes[1], 16);
    final n = TindeqProtocol.parse(bytes);
    expect(n.records.map((r) => r.timestampUs), [7, 12507]);
  });

  test('command responses: battery uint32 mV and version string', () {
    final batt = TindeqProtocol.parse(
      TindeqProtocol.encodeUint32Response(3912),
    );
    expect(batt.kind, TindeqNotificationKind.cmdResponse);
    expect(TindeqProtocol.payloadUint32(batt.payload), 3912);
    final ver = TindeqProtocol.parse(
      TindeqProtocol.encodeCmdResponse('1.2.5\u0000'.codeUnits),
    );
    expect(TindeqProtocol.payloadString(ver.payload), '1.2.5');
    expect(
      TindeqProtocol.parse([0x04, 0]).kind,
      TindeqNotificationKind.lowPower,
    );
  });

  test('battery percent is clamped and monotonic', () {
    expect(TindeqProtocol.batteryPercentFromMillivolts(3000), 0);
    expect(TindeqProtocol.batteryPercentFromMillivolts(4300), 100);
    expect(
      TindeqProtocol.batteryPercentFromMillivolts(3700),
      lessThan(TindeqProtocol.batteryPercentFromMillivolts(3900)),
    );
  });

  group('TindeqSampleDecoder', () {
    test('uses device timestamps, not arrival time', () {
      final d = TindeqSampleDecoder();
      final s = d.decode(const [
        TindeqWeightRecord(kg: 1, timestampUs: 500000),
        TindeqWeightRecord(kg: 2, timestampUs: 512500),
        TindeqWeightRecord(kg: 3, timestampUs: 525000),
      ]);
      expect(s.map((e) => e.timeMs), [0, 12, 25]);
      expect(s.last.rawTimestampUs, 525000);
    });

    test('drops duplicate deliveries of the same packet', () {
      final d = TindeqSampleDecoder();
      const packet = [
        TindeqWeightRecord(kg: 1, timestampUs: 0),
        TindeqWeightRecord(kg: 2, timestampUs: 12500),
      ];
      expect(d.decode(packet), hasLength(2));
      expect(d.decode(packet), isEmpty);
      expect(
        d.decode(const [TindeqWeightRecord(kg: 3, timestampUs: 25000)]),
        hasLength(1),
      );
    });

    test('re-bases when the device clock restarts', () {
      final d = TindeqSampleDecoder();
      d.decode(const [TindeqWeightRecord(kg: 1, timestampUs: 90000000)]);
      final s = d.decode(const [
        TindeqWeightRecord(kg: 2, timestampUs: 1000),
        TindeqWeightRecord(kg: 2, timestampUs: 13500),
      ]);
      expect(s.map((e) => e.timeMs), [0, 12]);
    });
  });
}
