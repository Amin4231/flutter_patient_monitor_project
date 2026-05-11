import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // 🔥 Firebase ready
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patient Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const DashboardPage(), // 🔥 Dashboard replaces counter
    );
  }
}

// ---------------- DASHBOARD PAGE ----------------
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Connect to Firebase Firestore
    final Stream<DocumentSnapshot> patientStream = FirebaseFirestore.instance
        .collection('patients')
        .doc('patient_1')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Monitor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: patientStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          var liveData = data['live_data'];

          // Example sensors
          bool tempStatus = liveData['temperature']['status'];
          double tempValue = liveData['temperature']['value'] ?? 0.0;

          bool hrStatus = liveData['heart_rate']['status'];
          int hrValue = liveData['heart_rate']['value'] ?? 0;

          bool spo2Status = liveData['spo2']['status'];
          int spo2Value = liveData['spo2']['value'] ?? 0;

          bool pressureStatus = liveData['pressure']['status'];
          double pressureValue = liveData['pressure']['value'] ?? 0.0;

          bool fallDetected = liveData['fall_detected'];
          bool medicineMissed = liveData['medicine_missed'];

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SensorCard(
                    title: '🌡 Temperature',
                    status: tempStatus,
                    value: tempValue.toStringAsFixed(1) + ' °C',
                  ),
                  SensorCard(
                    title: '❤️ Heart Rate',
                    status: hrStatus,
                    value: '$hrValue bpm',
                  ),
                  SensorCard(
                    title: '🫁 SpO₂',
                    status: spo2Status,
                    value: '$spo2Value %',
                  ),
                  SensorCard(
                    title: '🩸 Pressure',
                    status: pressureStatus,
                    value: '${pressureValue.toStringAsFixed(1)} mmHg',
                  ),
                  const SizedBox(height: 20),
                  AlertCard(
                    title: '⚠ Fall Detected',
                    active: fallDetected,
                  ),
                  AlertCard(
                    title: '💊 Medicine Missed',
                    active: medicineMissed,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- SENSOR CARD ----------------
class SensorCard extends StatelessWidget {
  final String title;
  final bool status;
  final String value;

  const SensorCard({
    super.key,
    required this.title,
    required this.status,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        subtitle: Text(
          status ? value : 'OFF',
          style: TextStyle(
            fontSize: 24,
            color: status ? Colors.green : Colors.red,
          ),
        ),
      ),
    );
  }
}

// ---------------- ALERT CARD ----------------
class AlertCard extends StatelessWidget {
  final String title;
  final bool active;

  const AlertCard({
    super.key,
    required this.title,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: active ? Colors.red[300] : Colors.grey[200],
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        subtitle: Text(
          active ? 'ALERT!' : 'Normal',
          style: TextStyle(
            fontSize: 24,
            color: active ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}