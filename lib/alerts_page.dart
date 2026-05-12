import 'package:flutter/material.dart';
import 'storage.dart';

class NotificationHistoryPage extends StatefulWidget {
  const NotificationHistoryPage({super.key});

  @override
  State<NotificationHistoryPage> createState() => _NotificationHistoryPageState();
}

class _NotificationHistoryPageState extends State<NotificationHistoryPage> {
  final HistoryStorage _storage = HistoryStorage();
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final data = await _storage.fetchHistory('notifications', limit: 100);
    setState(() {
      _notifications = data.reversed.toList(); // newest first
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification History'),
        backgroundColor: const Color(0xFF2EE59D),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? Center(
        child: Text(
          'No notifications yet',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final n = _notifications[index];
          final dt = DateTime.fromMillisecondsSinceEpoch(
              (n['timestamp'] as int) * 1000);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.notifications_active,
                  color: Colors.red),
              title: Text(
                n['title'] ?? 'Notification',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(n['body'] ?? ''),
              trailing: Text(
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          );
        },
      ),
    );
  }
}