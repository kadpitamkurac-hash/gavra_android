// Simple test to verify cancellation logic
import 'dart:convert';

void main() {
  // Simulate the "AI RADNIK TEST" record
  final Map<String, dynamic> testRecord = {
    'putnik_ime': 'AI RADNIK TEST',
    'polasci_po_danu': '''{
      "cet": {"bc":"05:00"},
      "pet": {"bc":"05:00"},
      "pon": {
        "bc":"05:00",
        "bc_otkazano":"2026-02-07T08:03:45.821466",
        "bc_otkazao_vozac":"Bojan",
        "bc_pokupljeno":"2026-02-07T08:04:04.689004",
        "bc_pokupljeno_vozac":"Bojan"
      },
      "sre": {"bc":"05:00"},
      "uto": {"bc":"05:00:00","vs":"17:00"}
    }'''
  };

  // Test isOtkazanForDayAndPlace logic
  print('Testing isOtkazanForDayAndPlace logic...\n');

  final isOtkazan = _isOtkazanForDayAndPlace(testRecord, 'pon', 'bc');
  print('Is otkazan for pon/bc? $isOtkazan');

  final isOtkazanVS = _isOtkazanForDayAndPlace(testRecord, 'pon', 'vs');
  print('Is otkazan for pon/vs? $isOtkazanVS');

  // Test with different day
  final isOtkazanSre = _isOtkazanForDayAndPlace(testRecord, 'sre', 'bc');
  print('Is otkazan for sre/bc? $isOtkazanSre');
}

bool _isOtkazanForDayAndPlace(
  Map<String, dynamic> rawMap,
  String dayKratica,
  String place,
) {
  final raw = rawMap['polasci_po_danu'];
  if (raw == null) {
    print('  ❌ polasci_po_danu is null');
    return false;
  }

  Map<String, dynamic>? decoded;
  if (raw is String) {
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>?;
      print('  ✓ Parsed JSON from string');
    } catch (e) {
      print('  ❌ JSON decode error: $e');
      return false;
    }
  } else if (raw is Map<String, dynamic>) {
    decoded = raw;
    print('  ✓ Already a Map');
  }

  if (decoded == null) {
    print('  ❌ Decoded is null');
    return false;
  }

  final dayData = decoded[dayKratica];
  print('  - Looking for dayKratica: $dayKratica');
  print('  - Available days: ${decoded.keys.toList()}');

  if (dayData == null || dayData is! Map) {
    print('  ❌ dayData not found or not a Map for $dayKratica');
    return false;
  }

  print('  - dayData keys: ${dayData.keys.toList()}');

  final otkazanoKey = '${place}_otkazano';
  final otkazanoTimestamp = dayData[otkazanoKey] as String?;

  print('  - Looking for key: $otkazanoKey');
  print('  - Found value: $otkazanoTimestamp');

  if (otkazanoTimestamp == null || otkazanoTimestamp.isEmpty) {
    print('  ❌ No timestamp for $otkazanoKey');
    return false;
  }

  print('  ✅ Found cancellation timestamp!');
  return true;
}
