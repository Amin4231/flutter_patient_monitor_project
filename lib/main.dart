import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'firebase_options.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

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

class PatientPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const PatientPage({super.key, required this.onToggleTheme});

  @override
  State<PatientPage> createState() => _PatientPageState();
}

class _PatientPageState extends State<PatientPage> {
  late final DatabaseReference dbRef;
  final AudioPlayer audioPlayer = AudioPlayer();

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

  // Other flags
  bool fallDetected = false;
  bool medicineAlarm = false;
  bool medicineTaken = false;
  int medicineTimestamp = 0;

  // Previous flags to detect changes for alarm
  bool prevFallDetected = false;
  bool prevMedicineAlarm = false;

  //bool emergencyAlarm = false;

  int lastHeartRate = 0;                 ////////////////////////

  // Last update timestamp
  DateTime? lastUpdate;

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

          if (data != null)
           {
          bool newFall = data['fall_detected'] ?? false;
          bool newMedicine = data['medicine_alarm'] ?? false;
          bool newMedicineTaken = data['medicine_taken'] ?? false;
          int newMedicineTimestamp = data['medicine_timestamp'] ?? 0;
          bool newEmergency = data['emergency_alarm'] ?? false;
    
          // Play the initial triggers (fall or medicine start) once when they first appear
          if (newFall && !prevFallDetected) {
            await _playAlarmOnceFalling();
          }
          if (newMedicine && !prevMedicineAlarm) {
          await _playAlarmOnceStart(); // new function for medicine start
          }

          // Emergency immediate trigger (keep behavior)
          if (newEmergency && !emergencyAlarm) {
            await _playAlarmOnceEmergency();
          }

          // Update state (this will update UI values)
          setState(() {
            // heart rate, temps, footsteps, etc.
            heartRateStatus = data['heart_beat']?['status'] ?? false;
            heartRate = data['heart_beat']?['value'] ?? 0;
            if (heartRateStatus) lastHeartRate = heartRate;

            objectTempStatus = data['temperature']?['object']?['status'] ?? false;
            objectTemp = (data['temperature']?['object']?['value'] as num?)?.toDouble() ?? 0.0;

            ambientTempStatus = data['temperature']?['ambient']?['status'] ?? false;
            ambientTemp = (data['temperature']?['ambient']?['value'] as num?)?.toDouble() ?? 0.0;

            footsteps = data['footsteps']?['value'] ?? 0;

            fallDetected = newFall;
            medicineAlarm = newMedicine;
            medicineTaken = newMedicineTaken;
            medicineTimestamp = newMedicineTimestamp;
            emergencyAlarm = newEmergency;

            prevFallDetected = newFall;
            prevMedicineAlarm = newMedicine;
          });

          // Timer and escalation handling AFTER state update:
          if (newMedicine && !newMedicineTaken && newMedicineTimestamp > 0) {
            // Only start timer if it's not already running
            if ((_countdownTimer == null || !_countdownTimer!.isActive) && !_hasEscalatedMedicineAlarm) {
              _startCountdownTimer();
            }
          }

           else {
            // medicine cleared or taken -> stop timer, reset escalation and stop audio
            _stopCountdownTimer();
            _hasEscalatedMedicineAlarm = false;
            if (newMedicineTaken) {
              await _stopAlarm();
            }
          }

          // If emergency cleared, stop alarm (optional)
          if (!newEmergency) {
            // if you want emergency to stop the sound when cleared:
            await _stopAlarm();
          }

          print("🔥 LIVE DATA: $data");
        }     

    });
  }

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
              print("⏳ Timer stopped because medicine taken");
            } else if (_localCountdown > 0) {
              _localCountdown--;
              print("⏳ Countdown tick: $_localCountdown");
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
    _localCountdown = 10; // reset for next alarm
    }

    void _checkMedicineEscalation() {
    if (medicineAlarm && !medicineTaken && !_hasEscalatedMedicineAlarm && _localCountdown == 0) {
      _hasEscalatedMedicineAlarm = true;
      _playAlarmOnceMissed();
    }
    } 

  @override
  void dispose() {
    _stopCountdownTimer();
    audioPlayer.dispose();
    super.dispose();
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
            SensorCard("Heart Beat", true, 
            heartRateStatus ? heartRate : lastHeartRate, 
            Icons.favorite, Colors.red),

            SensorCard("Object Temp", objectTempStatus, objectTemp, Icons.thermostat, Colors.orange),
            SensorCard("Ambient Temp", ambientTempStatus, ambientTemp, Icons.thermostat, Colors.blue),
            SensorCard("Footsteps", true, footsteps, Icons.directions_walk, Colors.green),
            FlagCard("Fall Detected", fallDetected, Icons.warning, Colors.red),
            FlagCard("Medicine Alarm", medicineAlarm, Icons.medical_services, Colors.purple),
            FlagCard("Emergency Alarm", emergencyAlarm, Icons.sos, Colors.red),

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
                  "Last updated: ${lastUpdate!.toLocal()}",
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
                  fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Reusable sensor card widget
class SensorCard extends StatelessWidget {
  final String title;
  final bool status;
  final dynamic value;
  final IconData icon;
  final Color color;

  const SensorCard(this.title, this.status, this.value, this.icon, this.color,
      {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          status ? value.toString() : "Sensor is off now",
          style: TextStyle(
              color: status ? Colors.green : Colors.red, fontSize: 16),
        ),
      ),
    );
  }
}

// Reusable flag card widget
class FlagCard extends StatelessWidget {
  final String title;
  final bool flag;
  final IconData icon;
  final Color color;

  const FlagCard(this.title, this.flag, this.icon, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          flag ? "Active" : "Inactive",
          style: TextStyle(color: flag ? Colors.green : Colors.red, fontSize: 16),
        ),
      ),
    );
  }
}
