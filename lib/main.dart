import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic>? savedUser;

  try {
    final profile =
        await SharedPreferencesAsync().getString('login_profile');

    if (profile != null) {
      final data = jsonDecode(profile);

      if (data is Map<String, dynamic> &&
          data['id'] is String &&
          (data['id'] as String).isNotEmpty &&
          data['name'] is String &&
          data['rollNumber'] is String) {
        savedUser = data;
      }
    }
  } catch (e) {
    debugPrint('Read saved login failed: $e');
  }

  runApp(MyApp(savedUser: savedUser));
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic>? savedUser;

  const MyApp({
    super.key,
    this.savedUser,
  });

  @override
  Widget build(BuildContext context) {
    final user = savedUser;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Maya',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      home: user == null
          ? const LoginScreen()
          : HomeScreen(
              name: user['name'] as String,
              rollNumber: user['rollNumber'] as String,
            ),
      routes: {
        '/login': (_) => const LoginScreen(),
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _rollController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _error = message;
    });
  }

  Future<void> _login() async {
    if (_loading) return;

    FocusScope.of(context).unfocus();

    final rollNumber = _rollController.text.trim();
    final password = _passwordController.text;

    if (rollNumber.isEmpty || password.isEmpty) {
      _showError('Wrong roll number or password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://api.maya.adityauniversity.in/node/api/login',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'roll_no': rollNumber,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      debugPrint('Login HTTP status: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode >= 500) {
        _showError(
          'Login server error (${response.statusCode}). Try again later.',
        );
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showError('Wrong roll number or password');
        return;
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        _showError('Unexpected server response.');
        return;
      }

      final userId = data['student_id'] ?? data['id'];

      if (data['status'].toString() != '1' ||
          userId is! String ||
          userId.isEmpty) {
        _showError('Wrong roll number or password');
        return;
      }

      final name = data['first_name']?.toString() ?? '';
      final loggedInRollNumber =
          data['roll_no']?.toString() ?? rollNumber;

      try {
        await SharedPreferencesAsync().setString(
          'login_profile',
          jsonEncode({
            'id': userId,
            'name': name,
            'rollNumber': loggedInRollNumber,
          }),
        );
      } on MissingPluginException catch (e) {
        debugPrint('Save login failed: $e');

        _showError(
          'Storage plugin is unavailable. Stop and rebuild the app.',
        );
        return;
      } on PlatformException catch (e) {
        debugPrint('Save login failed: $e');

        _showError(
          'Login succeeded, but saving failed (${e.code}).',
        );
        return;
      } catch (e, stackTrace) {
        debugPrint('Save login failed: $e');
        debugPrintStack(stackTrace: stackTrace);

        _showError(
          'Login succeeded, but saving failed (${e.runtimeType}).',
        );
        return;
      }

      if (!mounted) return;

      _passwordController.clear();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(
            name: name,
            rollNumber: loggedInRollNumber,
          ),
        ),
      );
    } on TimeoutException {
      _showError('Server took too long to respond. Please try again.');
    } on http.ClientException catch (e) {
      debugPrint('Login network error: $e');
      _showError('Cannot connect to the login server.');
    } on FormatException {
      _showError('Server returned an invalid response.');
    } catch (e) {
      debugPrint('Login failure type: ${e.runtimeType}');
      _showError('Unable to login. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _rollController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 56,
                        color: Colors.deepPurple,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Login',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _rollController,
                        enabled: !_loading,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Roll number',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        enabled: !_loading,
                        obscureText: _hidePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setState(() {
                                _hidePassword = !_hidePassword;
                              });
                            },
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}