import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

class Studentsscreen extends StatefulWidget {
  const Studentsscreen({super.key});

  @override
  State<Studentsscreen> createState() => _StudentsscreenState();
}

class _StudentsscreenState extends State<Studentsscreen> {
  static const _purple = Color(0xFF6852B3);
  static const _pageBackground = Color(0xFFFAF9FE);
  static const _borderColor = Color(0xFFE2DDF0);

  final _searchController = TextEditingController();

  Map<String, dynamic>? _student;
  bool _loading = false;
  bool _scannerOpen = false;
  bool _markingReceived = false;
  bool _needsStatusCheck = false;
  String? _error;

  bool get _busy => _loading || _scannerOpen || _markingReceived;

  int? get _shirtStatus {
    return int.tryParse(_student?['T_shirt_status']?.toString() ?? '');
  }

  String _value(String key) {
    final value = _student?[key]?.toString().trim() ?? '';
    return value.isEmpty ? 'Not specified' : value;
  }

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _error = message;
      _student = null;
    });
  }

  void _showMessage(String message, {bool success = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? const Color(0xFF287A49) : null,
        ),
      );
  }

  Future<void> _searchStudent([String? scannedRollNumber]) async {
    if (_loading || _markingReceived) return;

    final rollNumber = (scannedRollNumber ?? _searchController.text).trim();

    FocusScope.of(context).unfocus();

    if (rollNumber.isEmpty) {
      _showError('Enter a roll number.');
      return;
    }

    _searchController.text = rollNumber;

    setState(() {
      _loading = true;
      _student = null;
      _error = null;
      _needsStatusCheck = false;
    });

    try {
      final uri = Uri.https(
        'api.maya.adityauniversity.in',
        '/node/api/get-student-tshirt',
        {'rollNo': rollNumber},
      );

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      if (response.statusCode == 404) {
        _showError('No student found for this roll number.');
        return;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        _showError('Access denied. Check API authentication.');
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showError('Unable to load student (${response.statusCode}).');
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid response.');
      }

      if (decoded['success'] != true || decoded['data'] == null) {
        _showError('No student found for this roll number.');
        return;
      }

      final student = decoded['data'];

      if (student is! Map<String, dynamic> ||
          student['roll_no'] == null ||
          student['roll_no'].toString().trim().isEmpty) {
        throw const FormatException('Invalid student data.');
      }

      setState(() {
        _student = student;
      });
    } on TimeoutException {
      _showError('The server took too long. Please try again.');
    } on http.ClientException {
      _showError('Cannot connect to the server. Please try again.');
    } on FormatException {
      _showError('The server returned an unexpected response.');
    } catch (e) {
      debugPrint('Student lookup error type: ${e.runtimeType}');
      _showError('Unable to load student. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openScanner() async {
    if (_busy) return;

    FocusScope.of(context).unfocus();
    setState(() => _scannerOpen = true);

    try {
      final rollNumber = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const StudentBarcodeScanner()),
      );

      if (!mounted) return;

      if (rollNumber != null && rollNumber.trim().isNotEmpty) {
        await _searchStudent(rollNumber);
      }
    } finally {
      if (mounted) {
        setState(() => _scannerOpen = false);
      }
    }
  }

  Future<void> _markAsReceived() async {
    if (_student == null || _shirtStatus != 0 || _busy || _needsStatusCheck) {
      return;
    }

    final currentStudent = Map<String, dynamic>.from(_student!);
    final rollNumber = currentStudent['roll_no'].toString().trim();

    setState(() => _markingReceived = true);

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://api.maya.adityauniversity.in/node/api/update-student-tshirt',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'rollNo': rollNumber}),
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      if (response.statusCode == 401 || response.statusCode == 403) {
        _showMessage('Access denied. Unable to update this student.');
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _requireStatusCheck(
          'Could not confirm the update (${response.statusCode}). '
          'Check the current status before trying again.',
        );
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        throw const FormatException('Update was not confirmed.');
      }

      final updatedStudent = decoded['data'];

      if (updatedStudent is! Map<String, dynamic> ||
          updatedStudent['roll_no']?.toString().trim() != rollNumber ||
          updatedStudent['T_shirt_status']?.toString() != '1') {
        throw const FormatException('Unexpected update response.');
      }

      setState(() {
        // Preserve term1_payment because the update response omits it.
        _student = {...currentStudent, ...updatedStudent};
        _needsStatusCheck = false;
      });

      _showMessage('T-shirt marked as received successfully.', success: true);
    } on TimeoutException {
      _requireStatusCheck(
        'Request timed out. Check the current status to see '
        'whether the update completed.',
      );
    } on http.ClientException {
      _requireStatusCheck(
        'Connection interrupted. Check the current status '
        'before trying again.',
      );
    } catch (e) {
      debugPrint('T-shirt update error type: ${e.runtimeType}');

      _requireStatusCheck(
        'Could not confirm the update. Check the current status '
        'before trying again.',
      );
    } finally {
      if (mounted) {
        setState(() => _markingReceived = false);
      }
    }
  }

  void _requireStatusCheck(String message) {
    if (!mounted) return;

    setState(() => _needsStatusCheck = true);
    _showMessage(message);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 100),
        children: [
          _searchBar(),
          const SizedBox(height: 16),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: _purple)),
            ),

          if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFB33B3B)),
              ),
            ),

          if (!_loading && _student != null) _studentCard(),

          if (!_loading && _student == null && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Column(
                children: [
                  Icon(Icons.person_search_outlined, size: 48, color: _purple),
                  SizedBox(height: 12),
                  Text(
                    'Search a roll number or scan a student barcode.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF888195)),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        heroTag: 'student-barcode-scanner',
        onPressed: _busy ? null : _openScanner,
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tooltip: 'Scan student barcode',
        child: const Icon(Icons.qr_code_scanner, size: 26),
      ),
    );
  }

  Widget _searchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchStudent(),
            onChanged: (_) {
              if (_student != null || _error != null) {
                setState(() {
                  _student = null;
                  _error = null;
                  _needsStatusCheck = false;
                });
              }
            },
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Enter roll number',
              hintStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
              prefixIcon: const Icon(
                Icons.person_search_outlined,
                color: _purple,
                size: 22,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: const BorderSide(color: _borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: const BorderSide(color: _borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: const BorderSide(color: _purple, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : () => _searchStudent(),
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
            child: const Text(
              'Search',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _studentCard() {
    final status = _shirtStatus;
    final received = status == 1;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C49347A),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _studentHeader(),
                const SizedBox(height: 16),

                _fieldLabel('NAME'),
                const SizedBox(height: 6),
                Text(
                  _value('Name'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF171321),
                    height: 1.3,
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFEEEAF5)),
                ),

                _batchAndSize(),
                const SizedBox(height: 12),
                _paymentPanel(),
                const SizedBox(height: 8),
                _statusPanel(status),

                if (_needsStatusCheck) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'The update result is uncertain. Refresh the '
                    'student status before submitting again.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB66309)),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _searchStudent(_value('roll_no')),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Check current status'),
                  ),
                ],
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFFCFAFF),
              border: Border(top: BorderSide(color: Color(0xFFEEEAF5))),
            ),
            child: FilledButton.icon(
              onPressed: status == 0 && !_busy && !_needsStatusCheck
                  ? _markAsReceived
                  : null,
              icon: _markingReceived
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _purple,
                      ),
                    )
                  : Icon(
                      received
                          ? Icons.check_circle_outline
                          : Icons.inventory_2_outlined,
                      size: 20,
                    ),
              label: Text(
                _markingReceived
                    ? 'Saving...'
                    : received
                    ? 'Already received'
                    : 'Mark as received',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE6E1F2),
                disabledForegroundColor: const Color(0xFF817991),
                minimumSize: const Size(double.infinity, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF0EBFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.person_outline, color: _purple, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('STUDENT'),
              const SizedBox(height: 4),
              Text(
                _value('roll_no'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF171321),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF8F2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Text(
            'Found',
            style: TextStyle(
              color: Color(0xFF24845C),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _batchAndSize() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('BATCH'),
              const SizedBox(height: 6),
              Text(
                _value('Batch'),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: Color(0xFF171321),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _fieldLabel('SIZE'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EBFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _value('T_shirt'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _purple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentPanel() {
    final payment = _value('term1_payment');
    final paid = payment.toLowerCase() == 'paid';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: paid ? const Color(0xFFEBF8EF) : const Color(0xFFFFF5E6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: paid ? const Color(0xFFBFE8CE) : const Color(0xFFF2D6AD),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('TERM 1 PAYMENT'),
                const SizedBox(height: 5),
                Text(
                  payment,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: paid
                        ? const Color(0xFF287A49)
                        : const Color(0xFFAF680D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 15,
            backgroundColor: paid
                ? const Color(0xFF2B844C)
                : const Color(0xFFCC8B30),
            child: Icon(
              paid ? Icons.check : Icons.access_time,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel(int? status) {
    final received = status == 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: received ? const Color(0xFFEBF8EF) : const Color(0xFFFFF5E6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: received
                  ? const Color(0xFF2B844C)
                  : const Color(0xFFEF9828),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              received
                  ? 'T-shirt already received'
                  : status == 0
                  ? 'T-shirt not received yet'
                  : 'T-shirt status unavailable',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: received
                    ? const Color(0xFF287A49)
                    : const Color(0xFFB66309),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: Color(0xFF8A8498),
      ),
    );
  }
}

class StudentBarcodeScanner extends StatefulWidget {
  const StudentBarcodeScanner({super.key});

  @override
  State<StudentBarcodeScanner> createState() => _StudentBarcodeScannerState();
}

class _StudentBarcodeScannerState extends State<StudentBarcodeScanner> {
  bool _detected = false;

  void _onDetect(BarcodeCapture capture) {
    if (_detected || !mounted) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();

      if (value != null && value.isNotEmpty) {
        _detected = true;

        // The barcode should contain the roll number as plain text.
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan student barcode'),
        backgroundColor: const Color(0xFFE2DFFF),
        foregroundColor: const Color(0xFF242331),
      ),
      body: Column(
        children: [
          Expanded(child: MobileScanner(onDetect: _onDetect)),
          const SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Place the student barcode inside the camera view.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
