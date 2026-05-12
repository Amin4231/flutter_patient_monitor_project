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
class HistoryStorage {
  final DatabaseReference _root;

  HistoryStorage()
      : _root = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
    'https://patientmonitor-4f0e8-default-rtdb.europe-west1.firebasedatabase.app',
  ).ref('patient_1/history');

  // ──────────────────────────────────────────────────────────────────
  // CORE WRITE — all other save methods delegate here to avoid
  // duplication. Used directly by main.dart for sensor readings.
  // ──────────────────────────────────────────────────────────────────

  /// Write a numeric reading under [path] with the current timestamp.
  ///
  /// Called directly from main.dart:
  ///   _historyStorage.saveReading('heart_rate',          bpm.toDouble());
  ///   _historyStorage.saveReading('temperature_object',  °C);
  ///   _historyStorage.saveReading('temperature_ambient', °C);
  ///   _historyStorage.saveReading('footsteps',           count.toDouble());
  ///   _historyStorage.saveReading('medicine_alarm',      1.0);
  ///   _historyStorage.saveReading('emergency_alarm',     1.0);
  Future<void> saveReading(String path, double value) async {
    try {
      await _root.child(path).push().set({
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'value': value,
      });
    } catch (e) {
      // Silently swallow — a failed history write must never crash the app.
      // ignore: avoid_print
      print('[HistoryStorage] saveReading($path) failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // CONVENIENCE WRAPPERS (delegate to saveReading)
  // ──────────────────────────────────────────────────────────────────

  /// Record a fall event (value = 1.0 per occurrence).
  Future<void> saveFallEvent() => saveReading('fall_detected', 1.0);

  /// Record a medicine alarm trigger.
  Future<void> saveMedicineEvent() => saveReading('medicine_alarm', 1.0);

  /// Record an emergency / SOS trigger.
  Future<void> saveEmergencyEvent() => saveReading('emergency_alarm', 1.0);

  // ──────────────────────────────────────────────────────────────────
  // READ
  // ──────────────────────────────────────────────────────────────────

  /// Fetch the last [limit] entries for [path], sorted chronologically
  /// (oldest → newest).  Returns an empty list if no data exists.
  ///
  /// Each entry contains: { 'timestamp': int, 'value': num, 'key': String }
  Future<List<Map<String, dynamic>>> fetchHistory(
      String path, {
        int limit = 500,
      }) async {
    try {
      final snapshot =
      await _root.child(path).limitToLast(limit).get();

      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];

      final list = data.entries.map((e) {
        final item = Map<String, dynamic>.from(e.value as Map);
        item['key'] = e.key; // Firebase push-key (useful for debugging)
        return item;
      }).toList();

      // Ensure chronological order regardless of Firebase key ordering
      list.sort((a, b) =>
          (a['timestamp'] as int).compareTo(b['timestamp'] as int));

      return list;
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryStorage] fetchHistory($path) failed: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // MAINTENANCE (optional — call periodically or from a settings page)
  // ──────────────────────────────────────────────────────────────────

  /// Delete entries older than [days] days for a specific [path].
  ///
  /// Example — keep only last 30 days of heart-rate data:
  ///   await _historyStorage.pruneOlderThan('heart_rate', days: 30);
  Future<void> pruneOlderThan(String path, {int days = 30}) async {
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch ~/
          1000;

      final snapshot = await _root
          .child(path)
          .orderByChild('timestamp')
          .endAt(cutoff)
          .get();

      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      // Delete old entries concurrently
      await Future.wait(
        data.keys.map((key) => _root.child(path).child(key).remove()),
      );

      // ignore: avoid_print
      print(
          '[HistoryStorage] pruned ${data.length} old entries from $path');
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryStorage] pruneOlderThan($path) failed: $e');
    }
  }
}