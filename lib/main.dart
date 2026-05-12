// main.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'history_page.dart';
import 'storage.dart';
import 'alerts_page.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

const String kNotificationChannelId = 'mediguard_alerts';
const String kNotificationChannelName = 'MediGuard Alerts';
const String kNotificationChannelDesc = 'Vital signs and alarm notifications';

const int kBpmLow = 60;
const int kBpmHigh = 100;
const double kTempLow = 35.0;
const double kTempHigh = 37.5;

const int kNotifIdHeartRateLow = 1;
const int kNotifIdHeartRateHigh = 2;
const int kNotifIdTempHigh = 3;
const int kNotifIdTempLow = 4;
const int kNotifIdFall = 5;
const int kNotifIdMedicine = 6;
const int kNotifIdEmergency = 7;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initNotifications();
  runApp(const MediGuardApp());
}

Future<void> _initNotifications() async {
  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  await notificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );
  final androidPlugin = notificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
}

Future<void> _sendNotification({
  required int id,
  required String title,
  required String body,
  bool highPriority = false,
  String type = 'general',
}) async {
  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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

  await notificationsPlugin.show(
    id,
    title,
    body,
    NotificationDetails(android: androidDetails, iOS: iosDetails),
  );

  final storage = HistoryStorage();
  await storage.saveNotification(type: type, title: title, body: body);
}

class ThresholdChecker {
  bool _prevBpmLow = false, _prevBpmHigh = false;
  bool _prevTempHigh = false, _prevTempLow = false;
  bool _prevFall = false, _prevMedicine = false, _prevEmergency = false;

  Future<void> check({
    required int bpm,
    required bool bpmActive,
    required double objectTemp,
    required bool tempActive,
    required bool fallDetected,
    required bool medicineAlarm,
    required bool emergencyAlarm,
  }) async {
    if (bpmActive && bpm > 0) {
      final nowLow = bpm < kBpmLow;
      final nowHigh = bpm > kBpmHigh;

      if (nowLow && !_prevBpmLow) {
        await _sendNotification(
            id: kNotifIdHeartRateLow,
            title: '⚠️ Heart Rate Low',
            body: 'BPM $bpm < $kBpmLow',
            highPriority: true,
            type: 'heart_rate_low');
      } else if (!nowLow && _prevBpmLow) {
        await notificationsPlugin.cancel(kNotifIdHeartRateLow);
      }

      if (nowHigh && !_prevBpmHigh) {
        await _sendNotification(
            id: kNotifIdHeartRateHigh,
            title: '⚠️ Heart Rate High',
            body: 'BPM $bpm > $kBpmHigh',
            highPriority: true,
            type: 'heart_rate_high');
      } else if (!nowHigh && _prevBpmHigh) {
        await notificationsPlugin.cancel(kNotifIdHeartRateHigh);
      }
      _prevBpmLow = nowLow;
      _prevBpmHigh = nowHigh;
    }

    if (tempActive && objectTemp > 0) {
      final nowHigh = objectTemp > kTempHigh;
      final nowLow = objectTemp < kTempLow;

      if (nowHigh && !_prevTempHigh) {
        await _sendNotification(
            id: kNotifIdTempHigh,
            title: '🌡️ High Temperature',
            body: '${objectTemp.toStringAsFixed(1)}°C > $kTempHigh°C',
            highPriority: true,
            type: 'temp_high');
      } else if (!nowHigh && _prevTempHigh) {
        await notificationsPlugin.cancel(kNotifIdTempHigh);
      }

      if (nowLow && !_prevTempLow) {
        await _sendNotification(
            id: kNotifIdTempLow,
            title: '🌡️ Low Temperature',
            body: '${objectTemp.toStringAsFixed(1)}°C < $kTempLow°C',
            highPriority: true,
            type: 'temp_low');
      } else if (!nowLow && _prevTempLow) {
        await notificationsPlugin.cancel(kNotifIdTempLow);
      }
      _prevTempHigh = nowHigh;
      _prevTempLow = nowLow;
    }

    if (fallDetected && !_prevFall) {
      await _sendNotification(
          id: kNotifIdFall,
          title: '🆘 Fall Detected!',
          body: 'Patient may have fallen.',
          highPriority: true,
          type: 'fall');
    }
    _prevFall = fallDetected;

    if (medicineAlarm && !_prevMedicine) {
      await _sendNotification(
          id: kNotifIdMedicine,
          title: '💊 Medicine Time',
          body: 'Please take your medicine',
          type: 'medicine');
    } else if (!medicineAlarm && _prevMedicine) {
      await notificationsPlugin.cancel(kNotifIdMedicine);
    }
    _prevMedicine = medicineAlarm;

    if (emergencyAlarm && !_prevEmergency) {
      await _sendNotification(
          id: kNotifIdEmergency,
          title: '🚨 Emergency SOS!',
          body: 'Patient triggered SOS button!',
          highPriority: true,
          type: 'emergency');
    }
    _prevEmergency = emergencyAlarm;
  }
}

class MediGuardApp extends StatefulWidget {
  const MediGuardApp({super.key});

  @override
  State<MediGuardApp> createState() => _MediGuardAppState();
}

class _MediGuardAppState extends State<MediGuardApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF2EE59D),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF2EE59D),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: PatientDashboard(onToggleTheme: toggleTheme),
    );
  }
}

class PatientDashboard extends StatefulWidget {
  final VoidCallback onToggleTheme;

  const PatientDashboard({super.key, required this.onToggleTheme});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  late final DatabaseReference dbRef;
  final AudioPlayer audioPlayer = AudioPlayer();
  final ThresholdChecker _thresholdChecker = ThresholdChecker();
  final HistoryStorage _historyStorage = HistoryStorage();

  int _localCountdown = 10;
  Timer? _countdownTimer;

  bool heartRateStatus = true, objectTempStatus = true, ambientTempStatus = true;
  bool emergencyAlarm = false;

  int heartRate = 0, footsteps = 0, lastHeartRate = 0;
  double objectTemp = 0.0, ambientTemp = 0.0;

  bool fallDetected = false, medicineAlarm = false, medicineTaken = false;
  int medicineTimestamp = 0;

  bool prevFallDetected = false, prevMedicineAlarm = false;

  DateTime? lastHeartRateUpdate, lastTempUpdate, lastFootstepsUpdate,
      lastFallUpdate, lastMedicineUpdate, lastEmergencyUpdate;

  bool _isAlarmPlaying = false;
  bool _hasEscalatedMedicineAlarm = false;

  @override
  void initState() {
    super.initState();
    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://patientmonitor-4f0e8-default-rtdb.europe-west1.firebasedatabase.app',
    );
    dbRef = database.ref('patient_1/live_data');

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
      double newObjTemp = (data['temperature']?['object']?['value'] as num?)?.toDouble() ?? 0.0;
      bool newTempSt = data['temperature']?['object']?['status'] ?? false;
      double newAmbientTemp = (data['temperature']?['ambient']?['value'] as num?)?.toDouble() ?? 0.0;
      bool newAmbientSt = data['temperature']?['ambient']?['status'] ?? false;
      int newFootsteps = data['footsteps']?['value'] ?? 0;

      if (newFall && !prevFallDetected) await _playAlarmOnceFalling();
      if (newMedicine && !prevMedicineAlarm) await _playAlarmOnceStart();
      if (newEmergency && !emergencyAlarm) await _playAlarmOnceEmergency();

      await _thresholdChecker.check(
        bpm: newBpm,
        bpmActive: newBpmSt,
        objectTemp: newObjTemp,
        tempActive: newTempSt,
        fallDetected: newFall,
        medicineAlarm: newMedicine,
        emergencyAlarm: newEmergency,
      );

      final now = DateTime.now();

      // Force update all values without comparisons
      setState(() {
        heartRateStatus = newBpmSt;
        heartRate = newBpm;
        lastHeartRate = newBpm; // Always update lastHeartRate
        lastHeartRateUpdate = now;

        objectTempStatus = newTempSt;
        objectTemp = newObjTemp;
        ambientTempStatus = newAmbientSt;
        ambientTemp = newAmbientTemp;
        lastTempUpdate = now;

        footsteps = newFootsteps;
        lastFootstepsUpdate = now;

        fallDetected = newFall;
        medicineAlarm = newMedicine;
        medicineTaken = newMedicineTaken;
        medicineTimestamp = newMedicineTimestamp;
        emergencyAlarm = newEmergency;

        if (newFall) lastFallUpdate = now;
        if (newMedicine) lastMedicineUpdate = now;
        if (newEmergency) lastEmergencyUpdate = now;

        prevFallDetected = newFall;
        prevMedicineAlarm = newMedicine;
      });

      print('[DEBUG] Updated UI - HeartRate: $newBpm, ObjectTemp: $newObjTemp, AmbientTemp: $newAmbientTemp, Footsteps: $newFootsteps');

      // Force a second rebuild to ensure UI updates
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          setState(() {});
        }
      });
      // Save to history on every valid reading (not just changes)
      if (newBpmSt && newBpm > 0) {
        _historyStorage.saveReading('heart_rate', newBpm.toDouble());
        print('[DEBUG] Saved heart_rate: $newBpm');
      }
      if (newTempSt && newObjTemp > 0) {
        _historyStorage.saveReading('temperature_object', newObjTemp);
        print('[DEBUG] Saved temperature_object: $newObjTemp');
      }
      if (newAmbientSt && newAmbientTemp > 0) {
        _historyStorage.saveReading('temperature_ambient', newAmbientTemp);
        print('[DEBUG] Saved temperature_ambient: $newAmbientTemp');
      }
// Save footsteps every time (not just on change)
      _historyStorage.saveReading('footsteps', newFootsteps.toDouble());
      print('[DEBUG] Saved footsteps: $newFootsteps');

      if (newFall && !prevFallDetected) _historyStorage.saveFallEvent();
      if (newMedicine && !prevMedicineAlarm) _historyStorage.saveReading('medicine_alarm', 1.0);
      if (newEmergency && !emergencyAlarm) _historyStorage.saveReading('emergency_alarm', 1.0);

      if (newMedicine && !newMedicineTaken && newMedicineTimestamp > 0) {
        if ((_countdownTimer == null || !_countdownTimer!.isActive) && !_hasEscalatedMedicineAlarm) {
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

  Future<void> _playAlarmOnceFalling() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try { await audioPlayer.play(AssetSource('fall_emergency.mp3')); } catch (_) {}
      _isAlarmPlaying = false;
    }
  }

  Future<void> _playAlarmOnceStart() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try { await audioPlayer.play(AssetSource('starting.mp3')); } catch (_) {}
      _isAlarmPlaying = false;
    }
  }

  Future<void> _playAlarmOnceMissed() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try { await audioPlayer.play(AssetSource('medicine_missed.mp3')); } catch (_) {}
      _isAlarmPlaying = false;
    }
  }

  Future<void> _playAlarmOnceEmergency() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try { await audioPlayer.play(AssetSource('emergency.mp3')); } catch (_) {}
      _isAlarmPlaying = false;
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
    if (medicineAlarm && !medicineTaken && !_hasEscalatedMedicineAlarm && _localCountdown == 0) {
      _hasEscalatedMedicineAlarm = true;
      _playAlarmOnceMissed();
    }
  }

  Future<void> _stopAlarm() async {
    if (_isAlarmPlaying) {
      _isAlarmPlaying = false;
      try { await audioPlayer.stop(); } catch (_) {}
    }
  }

  @override
  void dispose() {
    _stopCountdownTimer();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'MediGuard',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isDark ? Icons.wb_sunny_outlined : Icons.brightness_6,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: widget.onToggleTheme,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Vitals Grid - moved above alerts
              GridView.count(
                key: const ValueKey('vitals_grid'),
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
                children: [
                  _GlassSensorCard(
                    title: 'Heart Rate',
                    value: heartRateStatus ? heartRate : lastHeartRate,
                    unit: 'BPM',
                    icon: Icons.favorite,
                    color: const Color(0xFF2EE59D),
                    lastUpdate: lastHeartRateUpdate,
                    isAbnormal: heartRateStatus && (heartRate < kBpmLow || heartRate > kBpmHigh),
                    onTap: () => _openHistory('Heart Rate', 'heart_rate', const Color(0xFF2EE59D), lastHeartRateUpdate,
                        low: kBpmLow.toDouble(), high: kBpmHigh.toDouble(), current: heartRateStatus ? heartRate.toDouble() : null),
                  ),
                  _GlassSensorCard(
                    title: 'Human Temp',
                    value: objectTempStatus ? objectTemp : null,
                    unit: '°C',
                    icon: Icons.thermostat,
                    color: Colors.orange,
                    lastUpdate: lastTempUpdate,
                    isAbnormal: objectTempStatus && (objectTemp < kTempLow || objectTemp > kTempHigh),
                    onTap: () => _openHistory('Object Temperature', 'temperature_object', Colors.orange, lastTempUpdate,
                        low: kTempLow, high: kTempHigh, current: objectTempStatus ? objectTemp : null),
                  ),
                  _GlassSensorCard(
                    title: 'Ambient Temp',
                    value: ambientTempStatus ? ambientTemp : null,
                    unit: '°C',
                    icon: Icons.thermostat,
                    color: Colors.blue,
                    lastUpdate: lastTempUpdate,
                    isAbnormal: false,
                    onTap: () => _openHistory('Ambient Temperature', 'temperature_ambient', Colors.blue, lastTempUpdate,
                        current: ambientTempStatus ? ambientTemp : null),
                  ),
                  _GlassSensorCard(
                    title: 'Footsteps',
                    value: footsteps,
                    unit: 'steps',
                    icon: Icons.directions_walk,
                    color: Colors.green,
                    lastUpdate: lastFootstepsUpdate,
                    isAbnormal: false,
                    onTap: () => _openHistory('Footsteps', 'footsteps', Colors.green, lastFootstepsUpdate,
                        current: footsteps.toDouble()),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Alerts Status Section
              _buildAlertsSection(isDark),

              if (medicineAlarm && !medicineTaken)
                _GlassBanner(text: 'Medicine time! ${_localCountdown}s left'),

              const SizedBox(height: 30),
              Text(
                'MediGuard esp Project',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationHistoryPage())),
        backgroundColor: const Color(0xFF2EE59D),
        child: const Icon(Icons.history, color: Colors.white),
      ),
    );
  }

  Widget _buildAlertsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alerts Status',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
        ),
        const SizedBox(height: 12),
        _AlertStatusCard(title: "Fall Detection", isActive: fallDetected, icon: Icons.warning_amber_rounded),
        const SizedBox(height: 10),
        _AlertStatusCard(title: "Medicine Reminder", isActive: medicineAlarm, icon: Icons.medication),
        const SizedBox(height: 10),
        _AlertStatusCard(title: "Emergency SOS", isActive: emergencyAlarm, icon: Icons.emergency),
      ],
    );
  }

  void _openHistory(String title, String path, Color color, DateTime? lastUpdate, {double? low, double? high, double? current}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryPage(
          title: title,
          unit: path.contains('temp') ? '°C' : (path == 'footsteps' ? 'steps' : 'BPM'),
          path: path,
          color: color,
          lastUpdate: lastUpdate,
          lowThreshold: low,
          highThreshold: high,
          currentValue: current,
        ),
      ),
    );
  }

  void _openFallHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryPage(
          title: 'Fall Events',
          unit: 'events',
          path: 'fall_detected',
          color: Colors.red,
          lastUpdate: lastFallUpdate,
          isFallDetection: true,
        ),
      ),
    );
  }
}

// New Fall Detection Card with timestamps
class _FallDetectionCard extends StatelessWidget {
  final bool fallDetected;
  final DateTime? lastFallUpdate;
  final VoidCallback? onTap;

  const _FallDetectionCard({
    required this.fallDetected,
    this.lastFallUpdate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = fallDetected ? Colors.red : Colors.green;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fallDetected ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fall Detection',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fallDetected ? "⚠️ FALL DETECTED" : "✓ No Fall Detected",
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (lastFallUpdate != null && fallDetected) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Detected at: ${_formatTime(lastFallUpdate!)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            if (fallDetected)
              const Chip(
                label: Text('ALERT'),
                backgroundColor: Colors.red,
                labelStyle: TextStyle(color: Colors.white, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')} on ${dt.day}/${dt.month}/${dt.year}';
  }
}

class _AlertStatusCard extends StatelessWidget {
  final String title;
  final bool isActive;
  final IconData icon;

  const _AlertStatusCard({required this.title, required this.isActive, required this.icon});

  String _getStatusText() {
    if (title == "Fall Detection") {
      return isActive ? "FALL DETECTED" : "No fall detected";
    }
    return isActive ? "ACTIVE" : "Normal";
  }

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.red : Colors.green;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(
                  _getStatusText(),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
          if (isActive)
            const Chip(
              label: Text('ALERT'),
              backgroundColor: Colors.red,
              labelStyle: TextStyle(color: Colors.white, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _GlassSensorCard extends StatelessWidget {
  final String title;
  final dynamic value;
  final String unit;
  final IconData icon;
  final Color color;
  final DateTime? lastUpdate;
  final bool isAbnormal;
  final VoidCallback? onTap;

  const _GlassSensorCard({
    required this.title,
    this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.lastUpdate,
    this.isAbnormal = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value != null
        ? (value is double ? value.toStringAsFixed(1) : value.toString())
        : '--';
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [(isAbnormal ? Colors.red : color).withOpacity(0.15), Colors.white.withOpacity(0.3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isAbnormal ? Colors.red : Colors.white24, width: 1),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isAbnormal ? Colors.red : color).withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: isAbnormal ? Colors.red : color, size: 22),
                    ),
                    if (isAbnormal)
                      const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isAbnormal ? Colors.red : null,
                  ),
                ),
                Text(unit, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassBanner extends StatelessWidget {
  final String text;
  const _GlassBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.medication, color: Colors.red),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}