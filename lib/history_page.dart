import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'storage.dart';
import 'dart:math' as math;

class HistoryPage extends StatefulWidget {
  final String title;
  final String unit;
  final String path;
  final Color color;
  final DateTime? lastUpdate;
  final bool isFallDetection;
  final double? lowThreshold;
  final double? highThreshold;
  final double? currentValue;

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
  List<Map<String, dynamic>> _rawData = [];
  double _avg = 0, _min = 0, _max = 0, _latest = 0;
  String _status = 'Normal';
  List<FlSpot> _spots = [];
  double _minY = 0, _maxY = 100;
  bool _showChart = true;
  List<DateTime> _fallTimes = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final raw = await _storage.fetchHistory(widget.path, limit: 300);
    print('[DEBUG] Raw data count for ${widget.path}: ${raw.length}');

    final points = <Map<String, dynamic>>[];

    for (final e in raw) {
      final ts = e['timestamp'] as int?;
      final val = (e['value'] as num?)?.toDouble();
      if (ts != null && val != null) {
        points.add({'timestamp': ts, 'value': val});
        print('[DEBUG] Loaded point: ts=$ts, val=$val');
      }
    }
    points.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

    // Remove duplicate timestamps (keep only the latest value for same timestamp)
    final uniquePoints = <Map<String, dynamic>>[];
    final seenTimestamps = <int>{};

    for (final point in points.reversed) {
      final ts = point['timestamp'] as int;
      if (!seenTimestamps.contains(ts)) {
        seenTimestamps.add(ts);
        uniquePoints.add(point);
      }
    }
    uniquePoints.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

    _rawData = List.from(uniquePoints);
    print('[DEBUG] Original points: ${points.length}, Unique points: ${uniquePoints.length}');

    if (widget.isFallDetection) {
      print('[DEBUG] Loading fall detection events. Found ${uniquePoints.length} points');
      _fallTimes = uniquePoints
          .map((p) {
        final ts = p['timestamp'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        print('[DEBUG] Fall event at: $date');
        return date;
      })
          .toList()
        ..sort((a, b) => b.compareTo(a));
      print('[DEBUG] Total fall events loaded: ${_fallTimes.length}');
    } else {
      if (uniquePoints.isNotEmpty) {
        final values = uniquePoints.map((p) => (p['value'] as num).toDouble()).toList();
        _latest = values.last;
        _avg = values.reduce((a, b) => a + b) / values.length;
        _min = values.reduce(math.min);
        _max = values.reduce(math.max);

        if (widget.currentValue != null) {
          _latest = widget.currentValue!;
        }

        if (widget.lowThreshold != null && _latest < widget.lowThreshold!) {
          _status = 'Low';
        } else if (widget.highThreshold != null && _latest > widget.highThreshold!) {
          _status = 'High';
        } else {
          _status = 'Normal';
        }

        _spots = uniquePoints
            .map((p) => FlSpot((p['timestamp'] as int).toDouble(), (p['value'] as num).toDouble()))
            .toList();

        _minY = (_min - 5).clamp(0, double.infinity);
        _maxY = _max + 5;
      }
    }

    setState(() => _loaded = true);
  }

  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.isFallDetection ? 'Delete All Fall Events' : 'Delete ${widget.title} History'),
        content: Text(
          'Are you sure you want to delete all ${widget.isFallDetection ? 'fall events' : widget.title + ' history'}?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteHistory();
    }
  }

  Future<void> _deleteHistory() async {
    setState(() => _loaded = false);

    try {
      await _storage.deleteHistory(widget.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.isFallDetection ? 'Fall events' : widget.title + ' history'} deleted'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete history: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _loaded = true);
    }
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
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete History',
            onPressed: _showDeleteDialog,
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

  Widget _buildGlassSummaryCard() {
    final bool abnormal = _status != 'Normal';
    final Color statusColor = abnormal ? Colors.red : Colors.green;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                (abnormal ? Colors.red : widget.color).withOpacity(0.2),
                Colors.white.withOpacity(0.4),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: abnormal ? Colors.red : Colors.white30, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(_status,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      '${_latest.toStringAsFixed(widget.unit == 'steps' ? 0 : 1)} ${widget.unit}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    if (widget.title == 'Footsteps')
                      const Text(
                        'steps taken today',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    if (widget.lastUpdate != null && widget.title != 'Footsteps')
                      Text(
                        'Last: ${_formatDate(widget.lastUpdate!)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              if (_spots.length >= 2)
                SizedBox(
                  width: 80,
                  height: 50,
                  child: LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: _spots.sublist(_spots.length - math.min(30, _spots.length)),
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
      ),
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        _statCard('Avg', _avg),
        _statCard('Min', _min),
        _statCard('Max', _max),
        _statCard(widget.title == 'Footsteps' ? 'Today' : 'Last', _latest),
      ]),
    );
  }

  Widget _statCard(String label, double value) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(widget.unit == 'steps' ? 0 : 1),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildChartView() {
    return Column(children: [
      _buildGlassSummaryCard(),
      _buildStatsRow(),
      const SizedBox(height: 8),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LineChart(_buildLineChartData()),
        ),
      ),
    ]);
  }

  LineChartData _buildLineChartData() {
    return LineChartData(
      minY: _minY,
      maxY: _maxY,
      gridData: FlGridData(show: true, drawVerticalLine: false),
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
            interval: _spots.length > 10 ? (_spots.last.x - _spots.first.x) / 5 : null,
            getTitlesWidget: (value, meta) {
              final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
              if (widget.title == 'Footsteps') {
                return Text(
                  '${dt.day}/${dt.month}',
                  style: const TextStyle(fontSize: 10),
                );
              } else {
                return Text(
                  '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10),
                );
              }
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
            final dt = DateTime.fromMillisecondsSinceEpoch(s.x.toInt() * 1000);
            if (widget.title == 'Footsteps') {
              return LineTooltipItem(
                '${dt.day}/${dt.month}/${dt.year}\n'
                    '${s.y.toStringAsFixed(0)} ${widget.unit}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            } else {
              return LineTooltipItem(
                '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}\n'
                    '${s.y.toStringAsFixed(1)} ${widget.unit}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }
          }).toList(),
        ),
      ),
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

  Widget _buildListView() {
    return Column(children: [
      _buildGlassSummaryCard(),
      _buildStatsRow(),
      const SizedBox(height: 8),
      Expanded(
        child: ListView.builder(
          itemCount: _rawData.length,
          itemBuilder: (context, index) {
            final entry = _rawData[_rawData.length - 1 - index];
            final val = (entry['value'] as num).toDouble();
            final ts = entry['timestamp'] as int;
            final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
            bool isAbnormal = false;
            if (widget.lowThreshold != null && val < widget.lowThreshold!) {
              isAbnormal = true;
            }
            if (widget.highThreshold != null && val > widget.highThreshold!) {
              isAbnormal = true;
            }
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isAbnormal ? Colors.red : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ListTile(
                leading: Icon(
                  isAbnormal ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: isAbnormal ? Colors.red : Colors.green,
                ),
                title: Text(
                  '${val.toStringAsFixed(widget.unit == 'steps' ? 0 : 1)} ${widget.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(_formatDate(dt)),
                trailing: isAbnormal
                    ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Alert', style: TextStyle(color: Colors.red, fontSize: 12)),
                )
                    : null,
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildFallTimeline() {
    if (_fallTimes.isEmpty) {
      return const Center(child: Text('No fall events recorded yet.', style: TextStyle(fontSize: 16)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _fallTimes.length,
      itemBuilder: (context, index) {
        final dt = _fallTimes[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.warning, color: Colors.red),
            title: const Text('Fall detected'),
            subtitle: Text(_formatDate(dt)),
            trailing: const Chip(
              label: Text('Alert', style: TextStyle(color: Colors.red, fontSize: 12)),
              backgroundColor: Color(0xFFFFCDD2),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}