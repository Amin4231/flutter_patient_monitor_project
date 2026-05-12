import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'storage.dart';

class HistoryPage extends StatefulWidget {
  final String title;
  final String unit;
  final String path; // e.g., 'heart_rate'
  final Color color;
  final DateTime? lastUpdate;

  const HistoryPage({
    super.key,
    required this.title,
    required this.unit,
    required this.path,
    required this.color,
    this.lastUpdate,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryStorage _storage = HistoryStorage();
  late Stream<List<Map<String, dynamic>>> _stream;
  List<FlSpot> _spots = [];
  double _minY = 0, _maxY = 100;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _stream = _storage.getHistory(widget.path);
    _stream.listen((data) {
      if (!mounted) return;
      final spots = <FlSpot>[];
      for (var item in data) {
        final ts = item['timestamp'] as int?;
        final val = (item['value'] as num?)?.toDouble();
        if (ts != null && val != null) {
          spots.add(FlSpot(ts.toDouble(), val));
        }
      }
      double minY = double.infinity, maxY = double.negativeInfinity;
      for (var spot in spots) {
        if (spot.y < minY) minY = spot.y;
        if (spot.y > maxY) maxY = spot.y;
      }
      setState(() {
        _spots = spots;
        _minY = minY.isFinite ? minY - 5 : 0;
        _maxY = maxY.isFinite ? maxY + 5 : 100;
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
      ),
      body: _loaded && _spots.isNotEmpty
          ? Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Last ${_spots.length} readings',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: _minY,
                  maxY: _maxY,
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final dt = DateTime.fromMillisecondsSinceEpoch(
                              value.toInt() * 1000);
                          return Text(
                              '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) =>
                            Text(value.toStringAsFixed(0),
                                style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _spots,
                      isCurved: true,
                      color: widget.color,
                      barWidth: 2,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: widget.color.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.lastUpdate != null)
              Text(
                'Last updated: ${widget.lastUpdate!.toString().substring(0, 19)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}