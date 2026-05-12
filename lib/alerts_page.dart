// lib/alerts_page.dart
import 'package:flutter/material.dart';

class AlertsPage extends StatelessWidget {
  final bool fallDetected;
  final bool medicineAlarm;
  final bool emergencyAlarm;

  const AlertsPage({
    super.key,
    required this.fallDetected,
    required this.medicineAlarm,
    required this.emergencyAlarm,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Alerts',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),

              _buildAlertCard(
                context,
                title: 'Fall Detected',
                active: fallDetected,
                icon: Icons.warning_amber_rounded,
                color: Colors.red,
              ),
              const SizedBox(height: 12),

              _buildAlertCard(
                context,
                title: 'Medicine Reminder',
                active: medicineAlarm,
                icon: Icons.medication,
                color: Colors.orange,
              ),
              const SizedBox(height: 12),

              _buildAlertCard(
                context,
                title: 'Emergency SOS',
                active: emergencyAlarm,
                icon: Icons.emergency,
                color: Colors.redAccent,
              ),

              const Spacer(),
              if (!fallDetected && !medicineAlarm && !emergencyAlarm)
                const Center(
                  child: Text(
                    'No active alerts',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertCard(
      BuildContext context, {
        required String title,
        required bool active,
        required IconData icon,
        required Color color,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active
            ? color.withOpacity(0.15)
            : (isDark ? Colors.white10 : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? color : Colors.grey.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 32,
            color: active ? color : Colors.grey,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: active
                    ? color
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
          if (active)
            const Chip(
              label: Text('ACTIVE'),
              backgroundColor: Colors.red,
              labelStyle: TextStyle(color: Colors.white, fontSize: 12),
            ),
        ],
      ),
    );
  }
}