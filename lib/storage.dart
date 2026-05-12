import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

/// Central storage class for all patient history data.
///
/// Firebase path layout:
///   patient_1/history/
///     heart_rate/        ← saveReading('heart_rate', bpm)
///     temperature_object/← saveReading('temperature_object', °C)
///     temperature_ambient/
///     footsteps/
///     fall_detected/     ← saveFallEvent()
///     medicine_alarm/    ← saveMedicineEvent() OR saveReading('medicine_alarm', 1.0)
///     emergency_alarm/   ← saveEmergencyEvent() OR saveReading('emergency_alarm', 1.0)
///     notifications/     ← saveNotification(type:, title:, body:)
class HistoryStorage {
  final DatabaseReference _root;

  HistoryStorage()
      : _root = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
    'https://patientmonitor-4f0e8-default-rtdb.europe-west1.firebasedatabase.app',
  ).ref('patient_1/history');

  // ──────────────────────────────────────────────────────────────────
  // CORE WRITE — numeric readings
  // ──────────────────────────────────────────────────────────────────

  Future<void> saveReading(String path, double value) async {
    try {
      await _root.child(path).push().set({
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'value': value,
      });
    } catch (e) {
      print('[HistoryStorage] saveReading($path) failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // NOTIFICATIONS — new method
  // ──────────────────────────────────────────────────────────────────

  /// Store a notification event (e.g., medicine reminder, emergency alert).
  Future<void> saveNotification({
    required String type,
    required String title,
    required String body,
  }) async {
    try {
      await _root.child('notifications').push().set({
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'type': type,
        'title': title,
        'body': body,
      });
    } catch (e) {
      print('[HistoryStorage] saveNotification failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // CONVENIENCE WRAPPERS
  // ──────────────────────────────────────────────────────────────────

  Future<void> saveFallEvent() => saveReading('fall_detected', 1.0);
  Future<void> saveMedicineEvent() => saveReading('medicine_alarm', 1.0);
  Future<void> saveEmergencyEvent() => saveReading('emergency_alarm', 1.0);

  // ──────────────────────────────────────────────────────────────────
  // READ
  // ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchHistory(
      String path, {
        int limit = 500,
      }) async {
    try {
      final snapshot = await _root.child(path).limitToLast(limit).get();
      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];

      final list = data.entries.map((e) {
        final item = Map<String, dynamic>.from(e.value as Map);
        item['key'] = e.key;
        return item;
      }).toList();

      list.sort((a, b) =>
          (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      return list;
    } catch (e) {
      print('[HistoryStorage] fetchHistory($path) failed: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // MAINTENANCE
  // ──────────────────────────────────────────────────────────────────

  Future<void> pruneOlderThan(String path, {int days = 30}) async {
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch ~/ 1000;

      final snapshot = await _root
          .child(path)
          .orderByChild('timestamp')
          .endAt(cutoff)
          .get();

      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      await Future.wait(
        data.keys.map((key) => _root.child(path).child(key).remove()),
      );
      print('[HistoryStorage] pruned ${data.length} old entries from $path');
    } catch (e) {
      print('[HistoryStorage] pruneOlderThan($path) failed: $e');
    }
  }
}