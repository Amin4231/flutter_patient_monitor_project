import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'storage.dart';

class HistoryPage extends StatefulWidget {
  final String title;
  final String unit;
  final String path;
  final Color color;
  final DateTime? lastUpdate;
  final bool isFallDetection; // true → show list, false → show chart

  const HistoryPage({
    super.key,
    required this.title,
    required this.unit,
    required this.path,
    required this.color,
    this.lastUpdate,
    this.isFallDetection = false,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryStorage _storage = HistoryStorage();
  bool _loaded = false;

  // For line chart
  List<FlSpot> _spots = [];
  double _minY = 0, _maxY = 100;

  // For fall list
  List<DateTime> _fallTimes = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final rawData = await _storage.fetchHistory(widget.path, limit: 200);

    if (widget.isFallDetection) {
      // Build list of fall times (most recent first)
      final times = <DateTime>[];
      for (final entry in rawData) {
        final ts = entry['timestamp'] as int?;
        if (ts != null) {
          times.add(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
        }
      }
      times.sort((a, b) => b.compareTo(a)); // newest first
      _fallTimes = times;
    } else {
      // Build line chart spots (timestamp in seconds as X, value as Y)
      final spots = <FlSpot>[];
      for (final entry in rawData) {
        final ts = entry['timestamp'] as int?;
        final val = (entry['value'] as num?)?.toDouble();
        if (ts != null && val != null) {
          spots.add(FlSpot(ts.toDouble(), val));
        }
      }
      spots.sort((a, b) => a.x.compareTo(b.x)); // chronological

      double minY = double.infinity, maxY = double.negativeInfinity;
      for (final s in spots) {
        if (s.y < minY) minY = s.y;
        if (s.y > maxY) maxY = s.y;
      }
      _spots = spots;
      _minY = minY.isFinite ? minY - 5 : 0;
      _maxY = maxY.isFinite ? maxY + 5 : 100;
      if (_minY < 0 && widget.path != 'footsteps') _minY = 0;
    }

    setState(() => _loaded = true);
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
          : widget.isFallDetection
          ? _buildFallList()
          : _buildLineChart(),
    );
  }

  Widget _buildLineChart() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: _spots.length > 10
                          ? (_spots.last.x - _spots.first.x) / 5
                          : null,
                      getTitlesWidget: (value, meta) {
                        final dt = DateTime.fromMillisecondsSinceEpoch(
                            (value * 1000).toInt());
                        return Text(
                          '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(
                            widget.unit == 'steps' ? 0 : 1),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots,
                    isCurved: true,
                    color: widget.color,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: _spots.length <= 50,
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          widget.color.withOpacity(0.3),
                          widget.color.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final dt = DateTime.fromMillisecondsSinceEpoch(
                          (s.x * 1000).toInt());
                      return LineTooltipItem(
                        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}\n${s.y.toStringAsFixed(1)} ${widget.unit}',
                        const TextStyle(
                            color: Colors.white, fontSize: 12),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          if (widget.lastUpdate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Last updated: ${widget.lastUpdate!.toString().substring(0, 19)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallList() {
    if (_fallTimes.isEmpty) {
      return const Center(
        child: Text('No fall events yet', style: TextStyle(fontSize: 16)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '${_fallTimes.length} fall event(s) detected',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _fallTimes.length,
            itemBuilder: (context, index) {
              final dt = _fallTimes[index];
              return ListTile(
                leading: const Icon(Icons.warning, color: Colors.red),
                title: Text('Fall detected'),
                subtitle: Text(
                  '${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}