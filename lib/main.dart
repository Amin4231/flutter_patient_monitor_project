import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'dart:async';
// ---- Phase 2 ----
import 'history_page.dart';
import 'storage.dart';

// ============================================================================
// NOTIFICATION SETUP
// ============================================================================
final FlutterLocalNotificationsPlugin notificationsPlugin =
FlutterLocalNotificationsPlugin();

// Notification channel ID (Android)
const String kNotificationChannelId = 'patient_monitor_alerts';
const String kNotificationChannelName = 'Patient Monitor Alerts';
const String kNotificationChannelDesc = 'Vital signs and alarm notifications';

// Thresholds (matching ESP32 defaults)
const int kBpmLow = 60;
const int kBpmHigh = 100;
const double kTempLow = 35.0;
const double kTempHigh = 37.5;

// Unique notification IDs (prevents stacking)
const int kNotifIdHeartRateLow = 1;
const int kNotifIdHeartRateHigh = 2;
const int kNotifIdTempHigh = 3;
const int kNotifIdTempLow = 4;
const int kNotifIdFall = 5;
const int kNotifIdMedicine = 6;
const int kNotifIdEmergency = 7;

// ============================================================================
// MAIN
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _initNotifications();

  runApp(const MyApp());
}

// ---------------------------------------------------------------------------
// Initialize notifications plugin
// ---------------------------------------------------------------------------
Future<void> _initNotifications() async {
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings iosSettings =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await notificationsPlugin.initialize(initSettings);

  // Request Android 13+ permission
  final androidPlugin =
  notificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
}

// ---------------------------------------------------------------------------
// Local function to send a notification
// ---------------------------------------------------------------------------
Future<void> _sendNotification({
  required int id,
  required String title,
  required String body,
  bool highPriority = false,
}) async {
  final AndroidNotificationDetails androidDetails =
  AndroidNotificationDetails(
    kNotificationChannelId,
    kNotificationChannelName,
    channelDescription: kNotificationChannelDesc,
    importance: highPriority ? Importance.max : Importance.high,
    priority: highPriority ? Priority.max : Priority.high,
    playSound: true,
    enableVibration: true,
    icon: '@mipmap/ic_launcher',
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  final NotificationDetails details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await notificationsPlugin.show(id, title, body, details);
}

// ============================================================================
// THRESHOLD CHECKER
// ============================================================================
class ThresholdChecker {
  // Previous states (prevents duplicate notifications)
  bool _prevBpmLow = false;
  bool _prevBpmHigh = false;
  bool _prevTempHigh = false;
  bool _prevTempLow = false;
  bool _prevFall = false;
  bool _prevMedicine = false;
  bool _prevEmergency = false;

  Future<void> check({
    required int bpm,
    required bool bpmActive,
    required double objectTemp,
    required bool tempActive,
    required bool fallDetected,
    required bool medicineAlarm,
    required bool emergencyAlarm,
  }) async {
    // ── Heart Rate ──────────────────────────────────────────────
    if (bpmActive && bpm > 0) {
      final nowLow = bpm < kBpmLow;
      final nowHigh = bpm > kBpmHigh;

      if (nowLow && !_prevBpmLow) {
        await _sendNotification(
          id: kNotifIdHeartRateLow,
          title: '⚠️ Heart Rate Low',
          body: 'BPM is $bpm — below $kBpmLow BPM',
          highPriority: true,
        );
      } else if (!nowLow && _prevBpmLow) {
        await notificationsPlugin.cancel(kNotifIdHeartRateLow);
      }

      if (nowHigh && !_prevBpmHigh) {
        await _sendNotification(
          id: kNotifIdHeartRateHigh,
          title: '⚠️ Heart Rate High',
          body: 'BPM is $bpm — above $kBpmHigh BPM',
          highPriority: true,
        );
      } else if (!nowHigh && _prevBpmHigh) {
        await notificationsPlugin.cancel(kNotifIdHeartRateHigh);
      }

      _prevBpmLow = nowLow;
      _prevBpmHigh = nowHigh;
    }

    // ── Temperature ─────────────────────────────────────────────
    if (tempActive && objectTemp > 0) {
      final nowHigh = objectTemp > kTempHigh;
      final nowLow = objectTemp < kTempLow;

      if (nowHigh && !_prevTempHigh) {
        await _sendNotification(
          id: kNotifIdTempHigh,
          title: '🌡️ High Temperature',
          body: '${objectTemp.toStringAsFixed(1)}°C — above $kTempHigh°C',
          highPriority: true,
        );
      } else if (!nowHigh && _prevTempHigh) {
        await notificationsPlugin.cancel(kNotifIdTempHigh);
      }

      if (nowLow && !_prevTempLow) {
        await _sendNotification(
          id: kNotifIdTempLow,
          title: '🌡️ Low Temperature',
          body: '${objectTemp.toStringAsFixed(1)}°C — below $kTempLow°C',
          highPriority: true,
        );
      } else if (!nowLow && _prevTempLow) {
        await notificationsPlugin.cancel(kNotifIdTempLow);
      }

      _prevTempHigh = nowHigh;
      _prevTempLow = nowLow;
    }

    // ── Fall Detected ───────────────────────────────────────────
    if (fallDetected && !_prevFall) {
      await _sendNotification(
        id: kNotifIdFall,
        title: '🆘 Fall Detected!',
        body: 'Patient may have fallen. Check immediately.',
        highPriority: true,
      );
    }
    _prevFall = fallDetected;

    // ── Medicine Alarm ─────────────────────────────────────────
    if (medicineAlarm && !_prevMedicine) {
      await _sendNotification(
        id: kNotifIdMedicine,
        title: '💊 Medicine Time',
        body: 'Please take your medicine now.',
      );
    } else if (!medicineAlarm && _prevMedicine) {
      await notificationsPlugin.cancel(kNotifIdMedicine);
    }
    _prevMedicine = medicineAlarm;

    // ── Emergency SOS ──────────────────────────────────────────
    if (emergencyAlarm && !_prevEmergency) {
      await _sendNotification(
        id: kNotifIdEmergency,
        title: '🚨 EMERGENCY SOS!',
        body: 'Patient triggered SOS button!',
        highPriority: true,
      );
    }
    _prevEmergency = emergencyAlarm;
  }
}

// ============================================================================
// APP ROOT
// ============================================================================
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patient Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: PatientPage(onToggleTheme: toggleTheme),
    );
  }
}

// ============================================================================
// PATIENT PAGE (MAIN UI)
// ============================================================================
class PatientPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const PatientPage({super.key, required this.onToggleTheme});

  @override
  State<PatientPage> createState() => _PatientPageState();
}

class _PatientPageState extends State<PatientPage> {
  late final DatabaseReference dbRef;
  final AudioPlayer audioPlayer = AudioPlayer();
  final ThresholdChecker _thresholdChecker = ThresholdChecker();

  // ---- Phase 2: history storage ----
  final HistoryStorage _historyStorage = HistoryStorage();

  int _localCountdown = 10;
  Timer? _countdownTimer;

  // Sensor status
  bool heartRateStatus = true;
  bool objectTempStatus = true;
  bool ambientTempStatus = true;
  bool emergencyAlarm = false;

  // Sensor values
  int heartRate = 0;
  int footsteps = 0;
  double objectTemp = 0.0;
  double ambientTemp = 0.0;
  int lastHeartRate = 0;

  // Flags
  bool fallDetected = false;
  bool medicineAlarm = false;
  bool medicineTaken = false;
  int medicineTimestamp = 0;

  // Previous flags (for audio triggers only)
  bool prevFallDetected = false;
  bool prevMedicineAlarm = false;

  // Timestamps
  DateTime? lastUpdate;
  DateTime? lastHeartRateUpdate;
  DateTime? lastTempUpdate;
  DateTime? lastFootstepsUpdate;
  DateTime? lastFallUpdate;
  DateTime? lastMedicineUpdate;
  DateTime? lastEmergencyUpdate;

  // Audio state
  bool _isAlarmPlaying = false;
  bool _hasEscalatedMedicineAlarm = false;

  @override
  void initState() {
    super.initState();

    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
      "https://patientmonitor-4f0e8-default-rtdb.europe-west1.firebasedatabase.app",
    );

    dbRef = database.ref("patient_1/live_data");

    dbRef.onValue.listen((event) async {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      bool newFall = data['fall_detected'] ?? false;
      bool newMedicine = data['medicine_alarm'] ?? false;
      bool newMedicineTaken = data['medicine_taken'] ?? false;
      int newMedicineTimestamp = data['medicine_timestamp'] ?? 0;
      bool newEmergency = data['emergency_alarm'] ?? false;

      int newBpm = data['heart_beat']?['value'] ?? 0;
      bool newBpmSt = data['heart_beat']?['status'] ?? false;
      double newObjTemp =
          (data['temperature']?['object']?['value'] as num?)?.toDouble() ??
              0.0;
      bool newTempSt = data['temperature']?['object']?['status'] ?? false;

      // ── Audio triggers ─────────────────────────────────────
      if (newFall && !prevFallDetected) await _playAlarmOnceFalling();
      if (newMedicine && !prevMedicineAlarm) await _playAlarmOnceStart();
      if (newEmergency && !emergencyAlarm) await _playAlarmOnceEmergency();

      // ── Notification threshold check ────────────────────────
      await _thresholdChecker.check(
        bpm: newBpm,
        bpmActive: newBpmSt,
        objectTemp: newObjTemp,
        tempActive: newTempSt,
        fallDetected: newFall,
        medicineAlarm: newMedicine,
        emergencyAlarm: newEmergency,
      );

      // ── Update state ───────────────────────────────────────
      final now = DateTime.now();
      setState(() {
        heartRateStatus = newBpmSt;
        heartRate = newBpm;
        if (heartRateStatus) lastHeartRate = heartRate;
        if (newBpmSt) lastHeartRateUpdate = now;

        objectTempStatus = newTempSt;
        objectTemp = newObjTemp;
        ambientTempStatus =
            data['temperature']?['ambient']?['status'] ?? false;
        ambientTemp =
            (data['temperature']?['ambient']?['value'] as num?)?.toDouble() ??
                0.0;
        if (newTempSt) lastTempUpdate = now;

        footsteps = data['footsteps']?['value'] ?? 0;
        lastFootstepsUpdate = now;

        fallDetected = newFall;
        medicineAlarm = newMedicine;
        medicineTaken = newMedicineTaken;
        medicineTimestamp = newMedicineTimestamp;
        emergencyAlarm = newEmergency;

        if (newFall) lastFallUpdate = now;
        if (newMedicine) lastMedicineUpdate = now;
        if (newEmergency) lastEmergencyUpdate = now;

        lastUpdate = now;

        prevFallDetected = newFall;
        prevMedicineAlarm = newMedicine;
      });

      // ---- Phase 2: save reading to history ----
      if (newBpmSt && newBpm > 0) {
        _historyStorage.saveReading('heart_rate', newBpm.toDouble());
      }
      if (newTempSt && newObjTemp > 0) {
        _historyStorage.saveReading('temperature_object', newObjTemp);
      }
      if (ambientTemp > 0) {
        _historyStorage.saveReading('temperature_ambient', ambientTemp);
      }
      _historyStorage.saveReading('footsteps', footsteps.toDouble());

      // ── Medicine timer ─────────────────────────────────────
      if (newMedicine && !newMedicineTaken && newMedicineTimestamp > 0) {
        if ((_countdownTimer == null || !_countdownTimer!.isActive) &&
            !_hasEscalatedMedicineAlarm) {
          _startCountdownTimer();
        }
      } else {
        _stopCountdownTimer();
        _hasEscalatedMedicineAlarm = false;
        if (newMedicineTaken) await _stopAlarm();
      }

      if (!newEmergency) await _stopAlarm();
    });
  }

  // ── Audio methods ─────────────────────────────────────────────────
  Future<void> _playAlarmOnceFalling() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try {
        await audioPlayer.play(AssetSource('fall_emergency.mp3'));
        _isAlarmPlaying = false;
      } catch (_) {}
    }
  }

  Future<void> _playAlarmOnceStart() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try {
        await audioPlayer.play(AssetSource('starting.mp3'));
        _isAlarmPlaying = false;
      } catch (_) {}
    }
  }

  Future<void> _playAlarmOnceMissed() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try {
        await audioPlayer.play(AssetSource('medicine_missed.mp3'));
        _isAlarmPlaying = false;
      } catch (_) {}
    }
  }

  Future<void> _playAlarmOnceEmergency() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try {
        await audioPlayer.play(AssetSource('emergency.mp3'));
        _isAlarmPlaying = false;
      } catch (_) {}
    }
  }

  void _startCountdownTimer() {
    _localCountdown = 10;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (medicineTaken) {
          timer.cancel();
          _localCountdown = 0;
        } else if (_localCountdown > 0) {
          _localCountdown--;
        } else {
          timer.cancel();
          _checkMedicineEscalation();
        }
      });
    });
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _localCountdown = 10;
  }

  void _checkMedicineEscalation() {
    if (medicineAlarm &&
        !medicineTaken &&
        !_hasEscalatedMedicineAlarm &&
        _localCountdown == 0) {
      _hasEscalatedMedicineAlarm = true;
      _playAlarmOnceMissed();
    }
  }

  Future<void> _stopAlarm() async {
    if (_isAlarmPlaying) {
      _isAlarmPlaying = false;
      try {
        await audioPlayer.stop();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _stopCountdownTimer();
    audioPlayer.dispose();
    super.dispose();
  }

  // ── Build method ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    int countdown = 0;
    if (medicineAlarm && !medicineTaken) {
      countdown = _localCountdown;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Patient Monitor"),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // ---- Phase 2: added onTap to each SensorCard ----
            SensorCard(
              title: "Heart Beat",
              status: true,
              value: heartRateStatus ? heartRate : lastHeartRate,
              icon: Icons.favorite,
              color: Colors.red,
              unit: "BPM",
              lastUpdate: lastHeartRateUpdate,
              warningLow: kBpmLow.toDouble(),
              warningHigh: kBpmHigh.toDouble(),
              currentDouble: heartRate.toDouble(),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryPage(
                  title: "Heart Rate",
                  unit: "BPM",
                  path: "heart_rate",
                  color: Colors.red,
                  lastUpdate: lastHeartRateUpdate,
                )));
              },
            ),
            SensorCard(
              title: "Object Temp",
              status: objectTempStatus,
              value: objectTemp,
              icon: Icons.thermostat,
              color: Colors.orange,
              unit: "°C",
              lastUpdate: lastTempUpdate,
              warningLow: kTempLow,
              warningHigh: kTempHigh,
              currentDouble: objectTemp,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryPage(
                  title: "Object Temperature",
                  unit: "°C",
                  path: "temperature_object",
                  color: Colors.orange,
                  lastUpdate: lastTempUpdate,
                )));
              },
            ),
            SensorCard(
              title: "Ambient Temp",
              status: ambientTempStatus,
              value: ambientTemp,
              icon: Icons.thermostat,
              color: Colors.blue,
              unit: "°C",
              lastUpdate: lastTempUpdate,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryPage(
                  title: "Ambient Temperature",
                  unit: "°C",
                  path: "temperature_ambient",
                  color: Colors.blue,
                  lastUpdate: lastTempUpdate,
                )));
              },
            ),
            SensorCard(
              title: "Footsteps",
              status: true,
              value: footsteps,
              icon: Icons.directions_walk,
              color: Colors.green,
              unit: "steps",
              lastUpdate: lastFootstepsUpdate,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryPage(
                  title: "Footsteps",
                  unit: "steps",
                  path: "footsteps",
                  color: Colors.green,
                  lastUpdate: lastFootstepsUpdate,
                )));
              },
            ),
            FlagCard(
              title: "Fall Detected",
              flag: fallDetected,
              icon: Icons.warning,
              color: Colors.red,
              lastUpdate: lastFallUpdate,
            ),
            FlagCard(
              title: "Medicine Alarm",
              flag: medicineAlarm,
              icon: Icons.medical_services,
              color: Colors.purple,
              lastUpdate: lastMedicineUpdate,
            ),
            FlagCard(
              title: "Emergency Alarm",
              flag: emergencyAlarm,
              icon: Icons.sos,
              color: Colors.red,
              lastUpdate: lastEmergencyUpdate,
            ),
            if (medicineAlarm && !medicineTaken)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  countdown > 0
                      ? "⏳ Time left: $countdown seconds"
                      : "⚠️ Alarm active!",
                  style: const TextStyle(fontSize: 16, color: Colors.purple),
                  textAlign: TextAlign.center,
                ),
              ),
            if (lastUpdate != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  "Last sync: ${_formatTime(lastUpdate!)}",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 20),
            Text(
              "created by Amin abo Elela",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// SENSOR CARD (ENHANCED with onTap for Phase 2)
// ============================================================================
class SensorCard extends StatelessWidget {
  final String title;
  final bool status;
  final dynamic value;
  final IconData icon;
  final Color color;
  final String unit;
  final DateTime? lastUpdate;
  final double? warningLow;
  final double? warningHigh;
  final double? currentDouble;
  // ---- Phase 2: tap callback ----
  final VoidCallback? onTap;

  const SensorCard({
    super.key,
    required this.title,
    required this.status,
    required this.value,
    required this.icon,
    required this.color,
    required this.unit,
    this.lastUpdate,
    this.warningLow,
    this.warningHigh,
    this.currentDouble,
    this.onTap,   // Phase 2
  });

  bool get _isOutOfRange {
    if (currentDouble == null) return false;
    if (warningLow != null && currentDouble! < warningLow!) return true;
    if (warningHigh != null && currentDouble! > warningHigh!) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final outOfRange = status && _isOutOfRange;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: outOfRange
          ? RoundedRectangleBorder(
        side: const BorderSide(color: Colors.red, width: 2.5),
        borderRadius: BorderRadius.circular(12),
      )
          : null,
      // ---- Phase 2: wrap ListTile with InkWell for tap ----
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ListTile(
          leading: Icon(icon, color: outOfRange ? Colors.red : color, size: 32),
          title: Row(
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (outOfRange)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.red),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status
                    ? (value is double
                    ? '${(value as double).toStringAsFixed(1)} $unit'
                    : '$value $unit')
                    : 'Sensor is off',
                style: TextStyle(
                  color: outOfRange
                      ? Colors.red
                      : (status ? Colors.green : Colors.red),
                  fontSize: 16,
                  fontWeight: outOfRange ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (lastUpdate != null)
                Text(
                  'Updated: ${_fmt(lastUpdate!)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
}

// ============================================================================
// FLAG CARD (unchanged)
// ============================================================================
class FlagCard extends StatelessWidget {
  final String title;
  final bool flag;
  final IconData icon;
  final Color color;
  final DateTime? lastUpdate;

  const FlagCard({
    super.key,
    required this.title,
    required this.flag,
    required this.icon,
    required this.color,
    this.lastUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: flag
          ? RoundedRectangleBorder(
        side: BorderSide(color: color, width: 2.5),
        borderRadius: BorderRadius.circular(12),
      )
          : null,
      child: ListTile(
        leading: Icon(icon, color: flag ? color : Colors.grey, size: 32),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              flag ? 'Active' : 'Inactive',
              style: TextStyle(
                color: flag ? Colors.red : Colors.green,
                fontSize: 16,
              ),
            ),
            if (lastUpdate != null && flag)
              Text(
                'Triggered: ${_fmt(lastUpdate!)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
}