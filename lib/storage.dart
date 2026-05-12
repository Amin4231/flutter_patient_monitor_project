import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class HistoryStorage {
  final DatabaseReference _root;

  HistoryStorage()
      : _root = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
    "https://patientmonitor-4f0e8-default-rtdb.europe-west1.firebasedatabase.app",
  ).ref("patient_1/history");

  // For numeric readings (heart rate, temperatures, footsteps)
  Future<void> saveReading(String path, double value) async {
    final entry = {
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'value': value,
    };
    await _root.child(path).push().set(entry);
  }

  // For fall detection (count occurrences)
  Future<void> saveFallEvent() async {
    final entry = {
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'value': 1, // each entry counts as one fall event
    };
    await _root.child('fall_detected').push().set(entry);
  }

  // Fetch raw data (limited to last 7 days for performance)
  Future<List<Map<String, dynamic>>> fetchHistory(String path,
      {int limit = 500}) async {
    final snapshot = await _root.child(path).limitToLast(limit).get();
    final data = snapshot.value as Map<dynamic, dynamic>?;
    if (data == null) return [];
    final list = data.entries.map((e) {
      final item = Map<String, dynamic>.from(e.value as Map);
      item['key'] = e.key;
      return item;
    }).toList();
    list.sort(
            (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
    return list;
  }
}