import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'history_page.dart';
import 'alerts_page.dart';   // ← MAKE SURE THIS LINE EXISTS
import 'storage.dart';

// ======================= NOTIFICATION SETUP =======================
final FlutterLocalNotificationsPlugin notificationsPlugin =
FlutterLocalNotificationsPlugin();

const String kNotificationChannelId   = 'mediguard_alerts';
const String kNotificationChannelName = 'MediGuard Alerts';
const String kNotificationChannelDesc = 'Vital signs and alarm notifications';

const int kBpmLow      = 60;
const int kBpmHigh     = 100;
const double kTempLow  = 35.0;
const double kTempHigh = 37.5;

const int kNotifIdHeartRateLow  = 1;
const int kNotifIdHeartRateHigh = 2;
const int kNotifIdTempHigh      = 3;
const int kNotifIdTempLow       = 4;
const int kNotifIdFall          = 5;
const int kNotifIdMedicine      = 6;
const int kNotifIdEmergency     = 7;

// ======================= MAIN =======================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initNotifications();
  runApp(const MediGuardApp());
}

Future<void> _initNotifications() async {
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('@mipmap/ic_launcher');
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

// ======================= NOTIFICATION HELPER =======================
Future<void> _sendNotification({
  required int id,
  required String title,
  required String body,
  bool highPriority = false,
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
}

// ======================= THRESHOLD CHECKER =======================
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
      final nowLow  = bpm < kBpmLow;
      final nowHigh = bpm > kBpmHigh;
      if (nowLow && !_prevBpmLow) {
        await _sendNotification(
            id: kNotifIdHeartRateLow,
            title: '⚠️ Heart Rate Low',
            body: 'BPM $bpm < $kBpmLow',
            highPriority: true);
      } else if (!nowLow && _prevBpmLow) {
        await notificationsPlugin.cancel(kNotifIdHeartRateLow);
      }
      if (nowHigh && !_prevBpmHigh) {
        await _sendNotification(
            id: kNotifIdHeartRateHigh,
            title: '⚠️ Heart Rate High',
            body: 'BPM $bpm > $kBpmHigh',
            highPriority: true);
      } else if (!nowHigh && _prevBpmHigh) {
        await notificationsPlugin.cancel(kNotifIdHeartRateHigh);
      }
      _prevBpmLow  = nowLow;
      _prevBpmHigh = nowHigh;
    }

    if (tempActive && objectTemp > 0) {
      final nowHigh = objectTemp > kTempHigh;
      final nowLow  = objectTemp < kTempLow;
      if (nowHigh && !_prevTempHigh) {
        await _sendNotification(
            id: kNotifIdTempHigh,
            title: '🌡️ High Temperature',
            body: '${objectTemp.toStringAsFixed(1)}°C > $kTempHigh°C',
            highPriority: true);
      } else if (!nowHigh && _prevTempHigh) {
        await notificationsPlugin.cancel(kNotifIdTempHigh);
      }
      if (nowLow && !_prevTempLow) {
        await _sendNotification(
            id: kNotifIdTempLow,
            title: '🌡️ Low Temperature',
            body: '${objectTemp.toStringAsFixed(1)}°C < $kTempLow°C',
            highPriority: true);
      } else if (!nowLow && _prevTempLow) {
        await notificationsPlugin.cancel(kNotifIdTempLow);
      }
      _prevTempHigh = nowHigh;
      _prevTempLow  = nowLow;
    }

    if (fallDetected && !_prevFall) {
      await _sendNotification(
          id: kNotifIdFall,
          title: '🆘 Fall Detected!',
          body: 'Patient may have fallen.',
          highPriority: true);
    }
    _prevFall = fallDetected;

    if (medicineAlarm && !_prevMedicine) {
      await _sendNotification(
          id: kNotifIdMedicine,
          title: '💊 Medicine Time',
          body: 'Please take your medicine');
    } else if (!medicineAlarm && _prevMedicine) {
      await notificationsPlugin.cancel(kNotifIdMedicine);
    }
    _prevMedicine = medicineAlarm;

    if (emergencyAlarm && !_prevEmergency) {
      await _sendNotification(
          id: kNotifIdEmergency,
          title: '🚨 Emergency SOS!',
          body: 'Patient triggered SOS button!',
          highPriority: true);
    }
    _prevEmergency = emergencyAlarm;
  }
}

// ======================= APP ROOT =======================
// FIX 1: _themeMode state + toggleTheme() instead of ThemeMode.system
class MediGuardApp extends StatefulWidget {
  const MediGuardApp({super.key});

  @override
  State<MediGuardApp> createState() => _MediGuardAppState();
}

class _MediGuardAppState extends State<MediGuardApp> {
  ThemeMode _themeMode = ThemeMode.light; // FIX 1: default light

  void toggleTheme() {
    setState(() {
      _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
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
      themeMode: _themeMode, // FIX 1: use state, not ThemeMode.system
      home: PatientDashboard(onToggleTheme: toggleTheme), // FIX 1: pass down
    );
  }
}

// ======================= MAIN DASHBOARD =======================
class PatientDashboard extends StatefulWidget {
  final VoidCallback onToggleTheme; // FIX 1: accept callback

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

  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
      'https://patientmonitor-4f0e8-default-rtdb.europe-west1.firebasedatabase.app',
    );
    dbRef = database.ref('patient_1/live_data');

    dbRef.onValue.listen((event) async {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      bool newFall             = data['fall_detected']    ?? false;
      bool newMedicine         = data['medicine_alarm']   ?? false;
      bool newMedicineTaken    = data['medicine_taken']   ?? false;
      int  newMedicineTimestamp = data['medicine_timestamp'] ?? 0;
      bool newEmergency        = data['emergency_alarm']  ?? false;

      int    newBpm       = data['heart_beat']?['value'] ?? 0;
      bool   newBpmSt     = data['heart_beat']?['status'] ?? false;
      double newObjTemp   =
          (data['temperature']?['object']?['value'] as num?)?.toDouble() ?? 0.0;
      bool   newTempSt    = data['temperature']?['object']?['status'] ?? false;
      double newAmbientTemp =
          (data['temperature']?['ambient']?['value'] as num?)?.toDouble() ?? 0.0;
      bool   newAmbientSt = data['temperature']?['ambient']?['status'] ?? false;

      // Audio triggers
      if (newFall && !prevFallDetected) await _playAlarmOnceFalling();
      if (newMedicine && !prevMedicineAlarm) await _playAlarmOnceStart();
      if (newEmergency && !emergencyAlarm) await _playAlarmOnceEmergency();

      // Notification thresholds
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
      setState(() {
        heartRateStatus = newBpmSt;
        heartRate       = newBpm;
        if (heartRateStatus) lastHeartRate = heartRate;
        if (newBpmSt) lastHeartRateUpdate = now;

        objectTempStatus  = newTempSt;
        objectTemp        = newObjTemp;
        ambientTempStatus = newAmbientSt;
        ambientTemp       = newAmbientTemp;
        if (newTempSt) lastTempUpdate = now;

        footsteps           = data['footsteps']?['value'] ?? 0;
        lastFootstepsUpdate = now;

        fallDetected       = newFall;
        medicineAlarm      = newMedicine;
        medicineTaken      = newMedicineTaken;
        medicineTimestamp  = newMedicineTimestamp;
        emergencyAlarm     = newEmergency;

        if (newFall)      lastFallUpdate      = now;
        if (newMedicine)  lastMedicineUpdate  = now;
        if (newEmergency) lastEmergencyUpdate = now;

        prevFallDetected  = newFall;
        prevMedicineAlarm = newMedicine;
      });

      // History logging
      if (newBpmSt && newBpm > 0) {
        _historyStorage.saveReading('heart_rate', newBpm.toDouble());
      }
      if (newTempSt && newObjTemp > 0) {
        _historyStorage.saveReading('temperature_object', newObjTemp);
      }
      if (newAmbientSt && newAmbientTemp > 0) {
        _historyStorage.saveReading('temperature_ambient', newAmbientTemp);
      }
      _historyStorage.saveReading('footsteps', footsteps.toDouble());

      if (newFall && !prevFallDetected) {
        _historyStorage.saveFallEvent();
      }

      // FIX 4: Log medicine and emergency events to history
      if (newMedicine && !prevMedicineAlarm) {
        _historyStorage.saveReading('medicine_alarm', 1.0);
      }
      if (newEmergency && !emergencyAlarm) {
        _historyStorage.saveReading('emergency_alarm', 1.0);
      }

      // Medicine countdown
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

  // ======================= AUDIO METHODS =======================
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

  // ======================= COUNTDOWN TIMER =======================
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

  // ======================= BUILD =======================
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: _currentTabIndex == 0
            ? _buildDashboard(isDark)
            : _buildAlertsView(), // FIX 5: pass live flags
      ),
      bottomNavigationBar: _buildBottomNav(isDark),
    );
  }

  // ----- Dashboard -----
  Widget _buildDashboard(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // FIX 1: top row now has the theme toggle button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MediGuard',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87),
              ),
              Row(
                children: [
                  // FIX 1: Dark/Light toggle button
                  IconButton(
                    icon: Icon(
                      isDark ? Icons.wb_sunny_outlined : Icons.brightness_6,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    tooltip: 'Toggle theme',
                    onPressed: widget.onToggleTheme,
                  ),
                  IconButton(
                    icon: Icon(Icons.settings_outlined,
                        color: isDark ? Colors.white70 : Colors.black54),
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // FIX 2: Heart rate widget is now tappable
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryPage(
                  title: 'Heart Rate',
                  unit: 'BPM',
                  path: 'heart_rate',
                  color: const Color(0xFF2EE59D),
                  lastUpdate: lastHeartRateUpdate,
                  lowThreshold: kBpmLow.toDouble(),
                  highThreshold: kBpmHigh.toDouble(),
                  currentValue: heartRateStatus ? heartRate.toDouble() : null,
                ),
              ),
            ),
            child: _CircularHeartRate(
              bpm: heartRateStatus ? heartRate : lastHeartRate,
              isActive: heartRateStatus,
              isAbnormal: heartRateStatus &&
                  (heartRate < kBpmLow || heartRate > kBpmHigh),
            ),
          ),
          const SizedBox(height: 16),

          // 2x2 glass cards grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _GlassSensorCard(
                title: 'Object Temp',
                value: objectTempStatus ? objectTemp : null,
                unit: '°C',
                icon: Icons.thermostat,
                color: Colors.orange,
                lastUpdate: lastTempUpdate,
                isAbnormal: objectTempStatus &&
                    (objectTemp < kTempLow || objectTemp > kTempHigh),
                onTap: () => _openHistory(
                    'Object Temperature', 'temperature_object',
                    Colors.orange, lastTempUpdate,
                    low: kTempLow, high: kTempHigh,
                    current: objectTempStatus ? objectTemp : null),
              ),
              _GlassSensorCard(
                title: 'Ambient Temp',
                value: ambientTempStatus ? ambientTemp : null,
                unit: '°C',
                icon: Icons.thermostat,
                color: Colors.blue,
                lastUpdate: lastTempUpdate,
                isAbnormal: false,
                onTap: () => _openHistory(
                    'Ambient Temperature', 'temperature_ambient',
                    Colors.blue, lastTempUpdate,
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
                onTap: () => _openHistory(
                    'Footsteps', 'footsteps',
                    Colors.green, lastFootstepsUpdate,
                    current: footsteps.toDouble()),
              ),
              _GlassSensorCard(
                title: 'Fall Alerts',
                value: null,
                unit: 'events',
                icon: Icons.warning,
                color: Colors.red,
                lastUpdate: lastFallUpdate,
                isAbnormal: fallDetected,
                onTap: () => _openFallHistory(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (medicineAlarm && !medicineTaken)
            _GlassBanner(
                text: 'Medicine time! ${_localCountdown}s left'),

          // FIX 3: Footer credit
          const SizedBox(height: 20),
          Text(
            'created by Amin abo Elela',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // FIX 5: pass live flags to AlertsPage
  Widget _buildAlertsView() {
    return AlertsPage(
      fallDetected: fallDetected,
      medicineAlarm: medicineAlarm,
      emergencyAlarm: emergencyAlarm,
    );
  }

  // ----- History navigation -----
  void _openHistory(
      String title,
      String path,
      Color color,
      DateTime? lastUpdate, {
        double? low,
        double? high,
        double? current,
      }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryPage(
          title: title,
          unit: path == 'footsteps'
              ? 'steps'
              : (path.contains('temp') ? '°C' : 'BPM'),
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

  // ----- Bottom navigation (floating pill) -----
  Widget _buildBottomNav(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 24, right: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (i) => setState(() => _currentTabIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF2EE59D),
          unselectedItemColor: isDark ? Colors.white54 : Colors.black38,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.notifications), label: 'Alerts'),
          ],
        ),
      ),
    );
  }
}

// ======================= GLASS SENSOR CARD =======================
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
        ? (value is double
        ? (value as double).toStringAsFixed(1)
        : value.toString())
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
                colors: [
                  (isAbnormal ? Colors.red : color).withOpacity(0.15),
                  Colors.white.withOpacity(0.3),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isAbnormal ? Colors.red : Colors.white24, width: 1),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                    (isAbnormal ? Colors.red : color).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      color: isAbnormal ? Colors.red : color, size: 22),
                ),
                const Spacer(),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isAbnormal
                        ? Colors.red
                        : Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                ),
                Text(unit,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
                if (lastUpdate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _fmt(lastUpdate!),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

// ======================= CIRCULAR HEART RATE =======================
class _CircularHeartRate extends StatelessWidget {
  final int bpm;
  final bool isActive;
  final bool isAbnormal;

  const _CircularHeartRate({
    required this.bpm,
    required this.isActive,
    this.isAbnormal = false,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = ((bpm - 40) / 140).clamp(0.0, 1.0);
    return Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                    isAbnormal ? Colors.red : const Color(0xFF2EE59D)),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$bpm',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: isAbnormal ? Colors.red : Colors.black87,
                  ),
                ),
                const Text('BPM',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                // Small hint that the widget is tappable
                const SizedBox(height: 4),
                const Text('tap for history',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= GLASS BANNER =======================
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
          Text(text,
              style: const TextStyle(
                  color: Colors.red, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}