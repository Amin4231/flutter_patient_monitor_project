import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'storage.dart';
import 'dart:math' as math;

// A data point used internally
class _DataPoint {
  final DateTime time;
  final double value;
  _DataPoint(this.time, this.value);
}

class HistoryPage extends StatefulWidget {
  final String title;
  final String unit;
  final String path;               // e.g. 'heart_rate'
  final Color color;
  final DateTime? lastUpdate;
  final bool isFallDetection;      // true → event timeline, no chart
  final double? lowThreshold;      // below → abnormal
  final double? highThreshold;     // above → abnormal
  final double? currentValue;      // latest live value (optional)

  const HistoryPage({
    super.key,
    required this.title,
    required this.unit,
    required this.path,
    required this.color,
    this.lastUpdate,
    this.isFallDetection = false,
    this.lowThreshold,
    this.highThreshold,
    this.currentValue,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryStorage _storage = HistoryStorage();
  bool _loaded = false;

  // All data points (sorted chronologically)
  List<_DataPoint> _points = [];

  // Stats
  double _avg = 0, _min = 0, _max = 0, _latest = 0;
  String _status = 'Normal';

  // For line chart
  List<FlSpot> _spots = [];
  double _minY = 0, _maxY = 100;

  // For event list (fall)
  List<DateTime> _fallTimes = [];

  // View mode (only for numeric metrics)
  bool _showChart = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final rawData = await _storage.fetchHistory(widget.path, limit: 300);
    final points = <_DataPoint>[];

    for (final entry in rawData) {
      final ts = entry['timestamp'] as int?;
      final val = (entry['value'] as num?)?.toDouble();
      if (ts != null && val != null) {
        points.add(_DataPoint(
            DateTime.fromMillisecondsSinceEpoch(ts * 1000), val));
      }
    }
    points.sort((a, b) => a.time.compareTo(b.time));

    if (widget.isFallDetection) {
      _fallTimes = points.map((p) => p.time).toList()
        ..sort((a, b) => b.compareTo(a)); // newest first
    } else {
      // Compute stats
      if (points.isNotEmpty) {
        final values = points.map((p) => p.value);
        _latest = values.last;
        _avg = values.reduce((a, b) => a + b) / values.length;
        _min = values.reduce(math.min);
        _max = values.reduce(math.max);

        // Determine status based on thresholds
        if (widget.lowThreshold != null && _latest < widget.lowThreshold!) {
          _status = 'Low';
        } else if (widget.highThreshold != null &&
            _latest > widget.highThreshold!) {
          _status = 'High';
        } else {
          _status = 'Normal';
        }

        // Build spots for chart
        _spots = points
            .map((p) => FlSpot(
            p.time.millisecondsSinceEpoch.toDouble() / 1000.0, p.value))
            .toList();

        _minY = (_min - 5).clamp(0, double.infinity);
        _maxY = (_max + 5);
        if (_minY < 0 && widget.unit == 'BPM') _minY = 0;
      }
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
        actions: [
          if (!widget.isFallDetection)
            IconButton(
              icon: Icon(_showChart ? Icons.list : Icons.show_chart),
              tooltip: _showChart ? 'List View' : 'Chart View',
              onPressed: () => setState(() => _showChart = !_showChart),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : widget.isFallDetection
          ? _buildFallTimeline()
          : _showChart
          ? _buildChartView()
          : _buildListView(),
    );
  }

  // -----------------------------------------------------------
  // Summary card
  // -----------------------------------------------------------
  Widget _buildSummaryCard() {
    final bool abnormal = _status != 'Normal';
    final Color statusColor = abnormal ? Colors.red : Colors.green;
    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      color: abnormal ? Colors.red.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(_status,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('$_latest ${widget.unit}',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold)),
                  if (widget.lastUpdate != null)
                    Text(
                      'Last updated: ${_formatDate(widget.lastUpdate!)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ),
            // Mini sparkline on the right
            if (_spots.length >= 2)
              SizedBox(
                width: 80,
                height: 50,
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: _spots.sublist(
                            _spots.length - math.min(30, _spots.length)),
                        isCurved: true,
                        color: widget.color,
                        barWidth: 1.5,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                    titlesData: FlTitlesData(show: false),
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    minY: _minY,
                    maxY: _maxY,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // Statistics panel
  // -----------------------------------------------------------
  Widget _buildStatsPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _statCard('Avg', _avg),
          _statCard('Min', _min),
          _statCard('Max', _max),
          _statCard('Last', _latest),
        ],
      ),
    );
  }

  Widget _statCard(String label, double value) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(widget.unit == 'steps' ? 0 : 1),
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // Chart view
  // -----------------------------------------------------------
  Widget _buildChartView() {
    return Column(
      children: [
        _buildSummaryCard(),
        _buildStatsPanel(),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: LineChart(_buildLineChartData()),
          ),
        ),
      ],
    );
  }

  LineChartData _buildLineChartData() {
    return LineChartData(
      minY: _minY,
      maxY: _maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(
              value.toStringAsFixed(widget.unit == 'steps' ? 0 : 1),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
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
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _spots,
          isCurved: true,
          color: widget.color,
          barWidth: 2.5,
          dotData: FlDotData(show: _spots.length <= 50),
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
          getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
            final dt = DateTime.fromMillisecondsSinceEpoch(
                (s.x * 1000).toInt());
            return LineTooltipItem(
              '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}\n${s.y.toStringAsFixed(1)} ${widget.unit}',
              const TextStyle(color: Colors.white, fontSize: 12),
            );
          }).toList(),
        ),
      ),
      // Highlight abnormal ranges on the chart
      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          if (widget.lowThreshold != null)
            HorizontalRangeAnnotation(
              y1: _minY,
              y2: widget.lowThreshold!,
              color: Colors.red.withOpacity(0.08),
            ),
          if (widget.highThreshold != null)
            HorizontalRangeAnnotation(
              y1: widget.highThreshold!,
              y2: _maxY,
              color: Colors.red.withOpacity(0.08),
            ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // List view
  // -----------------------------------------------------------
  Widget _buildListView() {
    return Column(
      children: [
        _buildSummaryCard(),
        _buildStatsPanel(),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _points.length,
            itemBuilder: (context, index) {
              final point = _points[_points.length - 1 - index]; // newest first
              bool isAbnormal = false;
              if (widget.lowThreshold != null &&
                  point.value < widget.lowThreshold!) isAbnormal = true;
              if (widget.highThreshold != null &&
                  point.value > widget.highThreshold!) isAbnormal = true;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isAbnormal ? Colors.red : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    isAbnormal
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: isAbnormal ? Colors.red : Colors.green,
                  ),
                  title: Text(
                    '${point.value.toStringAsFixed(widget.unit == 'steps' ? 0 : 1)} ${widget.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_formatDate(point.time)),
                  trailing: isAbnormal
                      ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Alert',
                        style: TextStyle(color: Colors.red)),
                  )
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // Event timeline (fall, medicine, emergency)
  // -----------------------------------------------------------
  Widget _buildFallTimeline() {
    return _fallTimes.isEmpty
        ? const Center(
        child: Text('No fall events recorded yet',
            style: TextStyle(fontSize: 16)))
        : ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _fallTimes.length,
      itemBuilder: (context, index) {
        final dt = _fallTimes[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.warning, color: Colors.red),
            title: const Text('Fall detected'),
            subtitle: Text(_formatDate(dt)),
            trailing: const Chip(
              label: Text('Alert', style: TextStyle(color: Colors.red)),
              backgroundColor: Colors.redAccent,
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}