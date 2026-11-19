import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart' as xlsx;
import 'package:file_picker/file_picker.dart';

class Reportscreen extends StatefulWidget {
  final String loggedInName;
  const Reportscreen({super.key,required this.loggedInName,});

  @override
  State<Reportscreen> createState() => _ReportscreenState();
}

class _ReportscreenState extends State<Reportscreen> {
  static const _purple = Color(0xFF6852B3);

  final List<Map<String, dynamic>> _students = [];

  String _selectedGroup = 'All';
  String _selectedStatus = 'All';

  bool _loading = false;
  bool _downloading = false;
  String? _error;

  bool get _busy => _loading || _downloading;

  static const _groups = [
    'All',
    'Drive Ready',
    'CodeForge',
    'Ignite Coders',
  ];

  static const _statuses = [
    'All',
    'Received',
    'Pending',
  ];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  String _text(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  String _groupName(Map<String, dynamic> student) {
    final group = _text(student['Placement_Section']);

    switch (group.toLowerCase()) {
      case 'drive ready':
        return 'Drive Ready';
      case 'codeforge':
        return 'CodeForge';
      case 'ignite coders':
        return 'Ignite Coders';
      default:
        return group.isEmpty ? 'Not specified' : group;
    }
  }

  int? _status(Map<String, dynamic> student) {
    return int.tryParse(_text(student['T_shirt_status']));
  }

  String _statusLabel(Map<String, dynamic> student) {
    switch (_status(student)) {
      case 1:
        return 'Received';
      case 0:
        return 'Pending';
      default:
        return 'Unknown';
    }
  }
String _issuedBy(Map<String, dynamic> student) {
  if (_status(student) != 1) return '—';

  final issuer = student['issuedBy'];

  if (issuer is Map) {
    final name = _text(
      issuer['first_name'] ?? issuer['name'] ?? issuer['Name'],
    );

    if (name.isNotEmpty) return name;
  } else if (issuer is String && issuer.trim().isNotEmpty) {
    return issuer.trim();
  }

  return widget.loggedInName.trim().isEmpty
      ? 'Name unavailable'
      : widget.loggedInName.trim();
}

  List<Map<String, dynamic>> _filterRows(
    List<Map<String, dynamic>> source,
    String group,
    String status,
  ) {
    final result = source.where((student) {
      final matchesGroup =
          group == 'All' || _groupName(student) == group;

      final matchesStatus = status == 'All' ||
          (status == 'Received' && _status(student) == 1) ||
          (status == 'Pending' && _status(student) == 0);

      return matchesGroup && matchesStatus;
    }).toList();

    result.sort((a, b) {
      final groupOrder = _groupName(a).compareTo(_groupName(b));

      return groupOrder != 0
          ? groupOrder
          : _text(a['roll_no']).compareTo(_text(b['roll_no']));
    });

    return result;
  }

  List<Map<String, dynamic>> get _filteredStudents {
    return _filterRows(
      _students,
      _selectedGroup,
      _selectedStatus,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchStudents() async {
    final response = await http.get(
      Uri.parse(
        'https://api.maya.adityauniversity.in/node/api/get-all-student-tshirt',
      ),
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ReportException(
        'Access denied. Check API authentication.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReportException(
        'Unable to load report (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic> ||
        decoded['success'] != true ||
        decoded['data'] is! List) {
      throw const FormatException('Unexpected response.');
    }

    final result = <Map<String, dynamic>>[];

    for (final row in decoded['data'] as List) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid student record.');
      }
      result.add(row);
    }

    return result;
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException) {
      return 'The server took too long. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to the server. Please retry.';
    }

    if (error is FormatException) {
      return 'The server returned an unexpected response.';
    }

    if (error is ReportException) {
      return error.message;
    }

    return 'Unable to complete the request. Please try again.';
  }

  Future<void> _loadStudents() async {
    if (_busy) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _fetchStudents();

      if (!mounted) return;

      setState(() {
        _students
          ..clear()
          ..addAll(rows);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = _errorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  Future<void> _downloadReport() async {
    if (_busy) return;

    final selectedGroup = _selectedGroup;
    final selectedStatus = _selectedStatus;

    setState(() {
      _downloading = true;
      _error = null;
    });

    try {
      // Fetch again so the export includes recent distributions.
      final latestStudents = await _fetchStudents();

      if (!mounted) return;

      setState(() {
        _students
          ..clear()
          ..addAll(latestStudents);
      });

      final rows = _filterRows(
        latestStudents,
        selectedGroup,
        selectedStatus,
      );

      if (rows.isEmpty) {
        _message('No students match the selected filters.');
        return;
      }

      final workbook = xlsx.Excel.createExcel();
      workbook.rename('Sheet1', 'T-shirt Report');

      final sheet = workbook['T-shirt Report'];

      const headers = [
        'Serial number',
        'Roll number',
        'Name',
        'T-shirt size',
        'Group',
        'Status',
        'Issued by',
      ];

      sheet.appendRow(
        headers.map((value) => xlsx.TextCellValue(value)).toList(),
      );

      for (var index = 0; index < rows.length; index++) {
        final student = rows[index];
        final size = _text(student['T_shirt']);

        sheet.appendRow([
          xlsx.IntCellValue(index + 1),
          xlsx.TextCellValue(_text(student['roll_no'])),
          xlsx.TextCellValue(_text(student['Name'])),
          xlsx.TextCellValue(
            size.isEmpty ? 'Not specified' : size,
          ),
          xlsx.TextCellValue(_groupName(student)),
          xlsx.TextCellValue(_statusLabel(student)),
          xlsx.TextCellValue(_issuedBy(student)),
        ]);
      }

      for (var column = 0; column < headers.length; column++) {
        sheet
            .cell(
              xlsx.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: 0,
              ),
            )
            .cellStyle = xlsx.CellStyle(bold: true);
      }

      sheet.setColumnWidth(0, 16);
      sheet.setColumnWidth(1, 20);
      sheet.setColumnWidth(2, 45);
      sheet.setColumnWidth(3, 18);
      sheet.setColumnWidth(4, 22);
      sheet.setColumnWidth(5, 16);
      sheet.setColumnWidth(6, 35);

      final encoded = workbook.encode();

      if (encoded == null || encoded.isEmpty) {
        throw const ReportException('Unable to create the Excel file.');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final groupPart = selectedGroup.replaceAll(' ', '_');

      final filename =
          'Tshirt_${groupPart}_${selectedStatus}_$timestamp.xlsx';

      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Save Excel report',
        fileName: filename,
        bytes: Uint8List.fromList(encoded),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (!mounted) return;

      if (savedUri == null) {
        _message('Save cancelled.');
      } else {
        _message('Excel report saved: ${rows.length} students.');
      }
    } catch (e) {
      debugPrint('Report export error type: ${e.runtimeType}');
      _message(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredStudents;
    final received = rows.where((row) => _status(row) == 1).length;
    final pending = rows.where((row) => _status(row) == 0).length;
    final unknown = rows.length - received - pending;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9FE),
      body: RefreshIndicator(
        onRefresh: _loadStudents,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Reports',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _loadStudents,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE2DDF0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Download T-shirt report',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select a group and distribution status.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 18),

                  DropdownButtonFormField<String>(
                    initialValue: _selectedGroup,
                    isExpanded: true,
                    decoration: _decoration('Group'),
                    items: _groups.map((group) {
                      return DropdownMenuItem(
                        value: group,
                        child: Text(group),
                      );
                    }).toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedGroup = value);
                          },
                  ),
                  const SizedBox(height: 14),

                  DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    isExpanded: true,
                    decoration: _decoration('T-shirt status'),
                    items: _statuses.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      );
                    }).toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedStatus = value);
                          },
                  ),
                  const SizedBox(height: 18),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _countChip('Total', rows.length),
                        _countChip('Received', received),
                        _countChip('Pending', pending),
                        if (unknown > 0)
                          _countChip('Unknown', unknown),
                      ],
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _downloadReport,
                    icon: _downloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      _downloading
                          ? 'Preparing Excel...'
                          : 'Download Excel',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Report preview',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            if (!_loading && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No students match these filters.'),
              ),

            // Preview is limited; the Excel export includes every match.
            for (final student in rows.take(10))
              Card(
                elevation: 0,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  title: Text(
                    _text(student['Name']),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${_text(student['roll_no'])}\n'
                    '${_groupName(student)} • '
                    'Size: ${_text(student['T_shirt']).isEmpty ? 'Not specified' : _text(student['T_shirt'])}\n'
                    'Issued by: ${_issuedBy(student)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    _statusLabel(student),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _status(student) == 1
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ),

            if (rows.length > 10)
              Text(
                'Showing 10 of ${rows.length} students. '
                'Excel includes all matching students.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFFAF9FE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 14,
      ),
    );
  }

  Widget _countChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EBFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $count',
        style: const TextStyle(
          fontSize: 12,
          color: _purple,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ReportException implements Exception {
  final String message;

  const ReportException(this.message);
}