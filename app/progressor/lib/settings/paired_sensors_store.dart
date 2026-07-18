import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Serialized paired Progressor entry.
class PairedSensorRecord {
  const PairedSensorRecord({
    required this.id,
    required this.name,
    this.bleRemoteId,
  });

  final String id;
  final String name;
  final String? bleRemoteId;

  factory PairedSensorRecord.fromJson(Map<String, dynamic> json) {
    return PairedSensorRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Progressor',
      bleRemoteId: json['bleRemoteId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (bleRemoteId != null) 'bleRemoteId': bleRemoteId,
      };
}

/// Persists the paired Progressor across app restarts.
class PairedSensorsStore {
  static const _key = 'progressor_paired_sensors_v1';

  Future<List<PairedSensorRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final entries = decoded['devices'] as List<dynamic>?;
      if (entries == null) return const [];
      return [
        for (final e in entries)
          if (e is Map<String, dynamic>) PairedSensorRecord.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<PairedSensorRecord> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'devices': [for (final d in devices) d.toJson()],
      }),
    );
  }
}
