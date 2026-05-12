import 'package:firebase_core/firebase_core.dart';   // <-- make sure this line exists
import 'package:firebase_database/firebase_database.dart';

class HistoryStorage {
  final DatabaseReference _root;

  HistoryStorage()
      : _root = FirebaseDatabase.instanceFor(
    app: Firebase.app(),      // <-- this requires the import above
    databaseURL:
    "https://patientmonitor-4f0e8-default-rtdb.europe-west1.firebasedatabase.app",
  ).ref("patient_1/history");

  Future<void> saveReading(String path, double value) async {
    final entry = {
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'value': value,
    };
    await _root.child(path).push().set(entry);
  }

  Stream<List<Map<String, dynamic>>> getHistory(String path,
      {int limit = 100}) {
    return _root.child(path).limitToLast(limit).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      final list = data.entries.map((e) {
        final item = Map<String, dynamic>.from(e.value as Map);
        item['key'] = e.key;
        return item;
      }).toList();
      list.sort(
              (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      return list;
    });
  }
}