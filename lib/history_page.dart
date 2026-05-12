import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'storage.dart';
import 'dart:math';

class HistoryPage extends StatefulWidget {
  final String title;
  final String unit;
  final String path;   // e.g., 'heart_rate', 'temperature_object', etc.
  final Color color;
  final DateTime? lastUpdate;
  final bool isFallDetection;   // special flag for fall events
  final bool isFootsteps;       // special flag for footsteps (sum instead of avg)

  const HistoryPage({
    super.key,
    required this.title,
    required this.unit,
    required this.path,
    required this.color,
    this.lastUpdate,
    this.isFallDetection = false,
    this.isFootsteps = false,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryStorage _storage = HistoryStorage();
  bool _loaded = false;

  // Daily aggregates (last 7 days)
  List<DailyBar> _dailyBars = [];
  double _dailyMaxY = 1;

  // Hourly aggregates (today)
  List<HourlyBar> _hourlyBars = [];
  double _hourlyMaxY = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Fetch raw data (enough to cover 7 days)
    final rawData = await _storage.fetchHistory(widget.path, limit: 2000);

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // --- Today's hourly aggregation ---
    final Map<int, List<double>> hourlyBuckets = {};
    for (int h = 0; h < 24; h++) hourlyBuckets[h] = [];

    for (var entry in rawData) {
      final ts = entry['timestamp'] as int?;
      if (ts == null) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      if (dt.isBefore(todayStart)) continue; // only today

      final hour = dt.hour;
      final val = (entry['value'] as num?)?.toDouble() ?? 0;
      hourlyBuckets[hour]!.add(val);
    }

    _hourlyBars = [];
    for (int h = 0; h < 24; h++) {
      final values = hourlyBuckets[h]!;
      if (values.isEmpty) {
        _hourlyBars.add(HourlyBar(hour: h, value: 0, count: 0));
      } else {
        double value;
        if (widget.isFootsteps) {
          value = values.reduce((a, b) => a + b); // sum for footsteps
        } else if (widget.isFallDetection) {
          value = values.length.toDouble(); // count
        } else {
          value = values.reduce((a, b) => a + b) / values.length; // average
        }
        _hourlyBars.add(HourlyBar(hour: h, value: value, count: values.length));
      }
    }

    // --- Daily aggregation (last 7 days including today) ---
    final Map<int, List<double>> dailyBuckets = {}; // key: weekday (1=Mon..7=Sun) for display order
    // We'll store by date string, then map to day-of-week
    final Map<String, List<double>> dateBuckets = {};
    for (int i = 6; i >= 0; i--) {
      final day = todayStart.subtract(Duration(days: i));
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      dateBuckets[key] = [];
    }

    for (var entry in rawData) {
      final ts = entry['timestamp'] as int?;
      if (ts == null) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      if (dateBuckets.containsKey(key)) {
        final val = (entry['value'] as num?)?.toDouble() ?? 0;
        dateBuckets[key]!.add(val);
      }
    }

    final sortedDays = dateBuckets.keys.toList()..sort();
    _dailyBars = [];
    for (final dayKey in sortedDays) {
      final values = dateBuckets[dayKey]!;
      double value;
      if (values.isEmpty) {
        value = 0;
      } else if (widget.isFootsteps) {
        value = values.reduce((a, b) => a + b);
      } else if (widget.isFallDetection) {
        value = values.length.toDouble();
      } else {
        value = values.reduce((a, b) => a + b) / values.length;
      }
      final parts = dayKey.split('-');
      final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      _dailyBars.add(DailyBar(weekday: _weekdayShort(date.weekday), value: value));
    }

    // Find max values for chart scaling
    _hourlyMaxY = _hourlyBars.map((e) => e.value).reduce(max) + 1;
    _dailyMaxY = _dailyBars.map((e) => e.value).reduce(max) + 1;
    if (_hourlyMaxY <= 0) _hourlyMaxY = 1;
    if (_dailyMaxY <= 0) _dailyMaxY = 1;

    setState(() => _loaded = true);
  }

  String _weekdayShort(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Today's hourly chart
            Text('Today (Hourly)',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  maxY: _hourlyMaxY,
                  barGroups: _hourlyBars.map((bar) {
                    return BarChartGroupData(
                      x: bar.hour,
                      barRods: [
                        BarChartRodData(
                          toY: bar.value,
                          color: widget.color,
                          width: 8,
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(widget.isFootsteps ? 0 : 1),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final hour = value.toInt();
                          return Text(
                            '$hour',
                            style: const TextStyle(fontSize: 9),
                          );
                        },
                        reservedSize: 20,
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Daily chart (last 7 days)
            Text('Last 7 Days',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  maxY: _dailyMaxY,
                  barGroups: _dailyBars.asMap().entries.map((entry) {
                    final index = entry.key;
                    final bar = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: bar.value,
                          color: widget.color,
                          width: 14,
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(widget.isFootsteps ? 0 : 1),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _dailyBars.length) return const Text('');
                          return Text(
                            _dailyBars[idx].weekday,
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                        reservedSize: 20,
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            if (widget.lastUpdate != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Last updated: ${widget.lastUpdate!.toString().substring(0, 19)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HourlyBar {
  final int hour;
  final double value;
  final int count;
  HourlyBar({required this.hour, required this.value, required this.count});
}

class DailyBar {
  final String weekday;
  final double value;
  DailyBar({required this.weekday, required this.value});
}