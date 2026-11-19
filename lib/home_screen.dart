import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tshirt_app/reportscreen.dart';
import 'package:tshirt_app/studentsscreen.dart';

const dashboardApiUrl =
    'https://api.maya.adityauniversity.in/node/api/get-all-student-tshirt';

class HomeScreen extends StatefulWidget {
  final String name;
  final String rollNumber;

  const HomeScreen({super.key, required this.name, required this.rollNumber});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() => _loggingOut = true);

    try {
      await SharedPreferencesAsync().remove('login_profile');

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      debugPrint('Logout error: $e');

      if (!mounted) return;

      setState(() => _loggingOut = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to logout. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 68,
        backgroundColor: const Color(0xFFE2DFFF),
        foregroundColor: const Color(0xFF242331),
        titleSpacing: 12,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFD4CEF5),
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Roll number: ${widget.rollNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_loggingOut)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _logout,
              tooltip: 'Logout',
              icon: const Icon(Icons.logout, size: 23),
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            const DashboardScreen(),
            const Studentsscreen(),
            Reportscreen(loggedInName: widget.name),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 65,
        selectedIndex: _selectedIndex,
        backgroundColor: const Color(0xFFF0EDF7),
        indicatorColor: const Color(0xFFE1DBFA),
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, size: 23),
            selectedIcon: Icon(Icons.dashboard, size: 23),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline, size: 23),
            selectedIcon: Icon(Icons.people, size: 23),
            label: 'Students',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined, size: 23),
            selectedIcon: Icon(Icons.bar_chart, size: 23),
            label: 'Report',
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardData? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http
          .get(
            Uri.parse(dashboardApiUrl),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const DashboardException(
          'Access denied. The API may require authentication.',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DashboardException(
          'Unable to load dashboard (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true ||
          decoded['summary'] is! Map<String, dynamic> ||
          decoded['data'] is! List) {
        throw const FormatException('Unexpected response.');
      }

      final result = DashboardData.fromJson(decoded);

      if (!mounted) return;

      setState(() => _data = result);
    } on TimeoutException {
      _setError('The server took too long. Please retry.');
    } on http.ClientException {
      _setError('Cannot connect to the server. Please retry.');
    } on FormatException {
      _setError('The server returned an unexpected response.');
    } on DashboardException catch (e) {
      _setError(e.message);
    } catch (e) {
      debugPrint('Dashboard error type: ${e.runtimeType}');
      _setError('Unable to load dashboard. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _loadDashboard,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!, style: const TextStyle(fontSize: 13)),
                  TextButton.icon(
                    onPressed: _loading ? null : _loadDashboard,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (data != null) ...[
            _overallProgress(data),
            const SizedBox(height: 10),
            ResponsiveTiles(
              minTileWidth: 140,
              maxColumns: 3,
              children: [
                StatCard(
                  label: 'Total students',
                  value: data.students,
                  icon: Icons.groups,
                  color: const Color(0xFF595C96),
                ),
                StatCard(
                  label: 'T-shirts allocated',
                  value: data.students,
                  icon: Icons.checkroom,
                  color: const Color(0xFF8B43A5),
                ),
                StatCard(
                  label: 'T-shirts distributed',
                  value: data.distributed,
                  icon: Icons.local_shipping,
                  color: const Color(0xFF39844E),
                ),
                StatCard(
                  label: 'Pending distribution',
                  value: data.pending,
                  icon: Icons.hourglass_bottom,
                  color: const Color(0xFFAA751F),
                ),
                StatCard(
                  label: 'Term 1 paid',
                  value: data.paid,
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF237A79),
                ),
                StatCard(
                  label: 'Term 1 not paid',
                  value: data.notPaid,
                  icon: Icons.pending_actions,
                  color: const Color(0xFFAF5751),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Groups',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (data.groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No student data available.'),
              ),
            for (final group in data.groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GroupCard(group: group),
              ),
          ],
        ],
      ),
    );
  }

  Widget _overallProgress(DashboardData data) {
    final ratio = data.students == 0 ? 0.0 : data.distributed / data.students;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1CDD9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Overall progress',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(ratio * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(value: ratio, color: const Color(0xFF585C96)),
          const SizedBox(height: 8),
          Text(
            '${data.distributed} of ${data.students} T-shirts handed out',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class ResponsiveTiles extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;

  const ResponsiveTiles({
    super.key,
    required this.children,
    this.minTileWidth = 90,
    this.maxColumns = 3,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;

        final columns = ((constraints.maxWidth + gap) / (minTileWidth + gap))
            .floor()
            .clamp(1, maxColumns)
            .toInt();

        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;

  const ProgressBar({super.key, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0).toDouble(),
        minHeight: 6,
        color: color,
        backgroundColor: Color.lerp(Colors.white, color, 0.2),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, color, 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color.lerp(Colors.white, color, 0.4)!),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GroupCard extends StatelessWidget {
  final GroupStats group;

  const GroupCard({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final ratio = group.total == 0 ? 0.0 : group.distributed / group.total;
    final color = group.color;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color.lerp(Colors.white, color, 0.5)!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: Color.lerp(Colors.white, color, 0.18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  foregroundColor: color,
                  child: const Icon(Icons.school_outlined, size: 19),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (group.year.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          group.year,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  children: [
                    Text(
                      '${(ratio * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('distributed', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProgressBar(value: ratio, color: color),
                const SizedBox(height: 12),
                ResponsiveTiles(
                  minTileWidth: 65,
                  maxColumns: 4,
                  children: [
                    _metric('Students', group.total),
                    _metric('Allocated', group.total),
                    _metric('Distributed', group.distributed),
                    _metric('Pending', group.pending),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Term 1: ${group.paid} paid • '
                  '${group.notPaid} not paid'
                  '${group.paymentUnknown == 0 ? '' : ' • ${group.paymentUnknown} unspecified'}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Size-wise T-shirts',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ResponsiveTiles(
                  minTileWidth: 80,
                  maxColumns: 3,
                  children: [
                    for (final size in group.sortedSizes)
                      _sizeTile(size, group.sizes[size]!, color),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  Widget _sizeTile(String size, SizeStats stats, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, color, 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  size,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${stats.total}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Given ${stats.distributed}',
            style: const TextStyle(fontSize: 11),
          ),
          Text(
            'Left ${stats.total - stats.distributed}',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class DashboardData {
  final int students;
  final int distributed;
  final int pending;
  final int paid;
  final int notPaid;
  final List<GroupStats> groups;

  DashboardData({
    required this.students,
    required this.distributed,
    required this.pending,
    required this.paid,
    required this.notPaid,
    required this.groups,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    final rows = json['data'] as List;
    final grouped = <String, GroupStats>{};

    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid student record.');
      }

      final rawName = row['Placement_Section']?.toString().trim() ?? '';

      final String name;

      switch (rawName.toLowerCase()) {
        case 'ignite coders':
          name = 'Ignite Coders';
          break;
        case 'codeforge':
          name = 'CodeForge';
          break;
        case 'drive ready':
          name = 'Drive Ready';
          break;
        default:
          name = rawName.isEmpty ? 'Unassigned' : rawName;
      }

      final group = grouped.putIfAbsent(name, () => GroupStats(name));

      group.add(row);
    }

    final groups = grouped.values.toList()
      ..sort((a, b) {
        final comparison = a.order.compareTo(b.order);

        return comparison == 0 ? a.name.compareTo(b.name) : comparison;
      });

    return DashboardData(
      students: _count(summary['total_students']),
      distributed: _count(summary['tshirt_issued']),
      pending: _count(summary['tshirt_pending']),
      paid: _count(summary['term1_paid']),
      notPaid: _count(summary['term1_not_paid']),
      groups: groups,
    );
  }

  static int _count(dynamic value) {
    final count = int.tryParse(value.toString());

    if (count == null || count < 0) {
      throw const FormatException('Invalid summary count.');
    }

    return count;
  }
}

class GroupStats {
  final String name;

  int total = 0;
  int distributed = 0;
  int paid = 0;
  int notPaid = 0;
  int paymentUnknown = 0;

  final Map<String, SizeStats> sizes = {
    for (final size in ['XS', 'S', 'M', 'L', 'XL', 'XXL']) size: SizeStats(),
  };

  GroupStats(this.name);

  int get pending => total - distributed;

  // Year labels match your reference screenshots.
  String get year {
    switch (name) {
      case 'Ignite Coders':
        return '1st Year';
      case 'CodeForge':
        return '2nd Year';
      case 'Drive Ready':
        return '3rd Year';
      default:
        return '';
    }
  }

  int get order {
    switch (name) {
      case 'Ignite Coders':
        return 0;
      case 'CodeForge':
        return 1;
      case 'Drive Ready':
        return 2;
      default:
        return 3;
    }
  }

  Color get color {
    switch (name) {
      case 'Ignite Coders':
        return const Color(0xFFE96B22);
      case 'CodeForge':
        return const Color(0xFF398D88);
      case 'Drive Ready':
        return const Color(0xFF6963A7);
      default:
        return const Color(0xFF607D8B);
    }
  }

  List<String> get sortedSizes {
    const order = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL', 'XXXXL'];

    int rank(String size) {
      if (size == 'Not specified') return 1000;

      final index = order.indexOf(size);
      return index < 0 ? 100 : index;
    }

    final result = sizes.keys.toList();

    result.sort((a, b) {
      final comparison = rank(a).compareTo(rank(b));
      return comparison == 0 ? a.compareTo(b) : comparison;
    });

    return result;
  }

  void add(Map<String, dynamic> row) {
    final status = row['T_shirt_status'].toString();

    if (status != '0' && status != '1') {
      throw const FormatException('Unknown T-shirt status.');
    }

    total++;

    final issued = status == '1';
    if (issued) distributed++;

    final payment = row['term1_payment']?.toString().trim().toLowerCase();

    if (payment == 'paid') {
      paid++;
    } else if (payment == 'not paid') {
      notPaid++;
    } else {
      paymentUnknown++;
    }

    final rawSize = row['T_shirt']?.toString().trim().toUpperCase() ?? '';

    final size = rawSize.isEmpty ? 'Not specified' : rawSize;
    final stats = sizes.putIfAbsent(size, () => SizeStats());

    stats.total++;
    if (issued) stats.distributed++;
  }
}

class SizeStats {
  int total = 0;
  int distributed = 0;
}

class DashboardException implements Exception {
  final String message;

  const DashboardException(this.message);
}

// class ReportScreen extends StatelessWidget {
//   const ReportScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return const Center(child: Text('Report', style: TextStyle(fontSize: 20)));
//   }
// }
