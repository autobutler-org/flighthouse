import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

const _apiOrigin = String.fromEnvironment('FIXTURE_API_ORIGIN');
const _tokenKey = 'web_fixture_token';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final SemanticsHandle? semantics =
      const bool.fromEnvironment('FLIGHTHOUSE_SEMANTICS')
      ? WidgetsBinding.instance.ensureSemantics()
      : null;
  runApp(FixtureApp(semantics: semantics));
}

class FixtureApp extends StatelessWidget {
  const FixtureApp({required this.semantics, super.key});

  final SemanticsHandle? semantics;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: semantics == null
          ? 'Web fixture without semantics'
          : 'Web fixture',
      debugShowCheckedModeBanner: false,
      onGenerateRoute: _route,
    );
  }
}

Route<void> _route(RouteSettings settings) {
  final page = switch (settings.name) {
    '/login' => const LoginPage(),
    '/account' => const AccountPage(),
    '/public' => const PublicPage(),
    _ => const PublicPage(),
  };
  return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
}

class PublicPage extends StatelessWidget {
  const PublicPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: _Main(label: 'Public', child: Text('Public')),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _startSubmit() {
    unawaited(_submit());
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _login(_username.text, _password.text);
      if (!mounted) return;
      if (token == null) {
        setState(() => _error = 'Sign in failed');
        return;
      }
      _writeToken(token);
      await Navigator.of(context).pushReplacementNamed('/account');
    } on http.ClientException {
      if (mounted) setState(() => _error = 'Sign in failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _Main(
        label: 'Sign in form',
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                identifier: 'username',
                child: TextField(
                  controller: _username,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Username'),
                  textInputAction: TextInputAction.next,
                ),
              ),
              Semantics(
                identifier: 'password',
                child: TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _startSubmit(),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                identifier: 'sign-in',
                button: true,
                label: 'Sign in',
                onTap: _busy ? null : _startSubmit,
                child: ExcludeSemantics(
                  child: FilledButton(
                    onPressed: _busy ? null : _startSubmit,
                    child: const Text('Sign in'),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  var _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = _readToken();
    if (token == null) {
      _goLogin();
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$_apiOrigin/account'),
        headers: {'authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        _clearToken();
        _goLogin();
        return;
      }
      setState(() => _ready = true);
    } on http.ClientException {
      if (!mounted) return;
      _clearToken();
      _goLogin();
    }
  }

  void _goLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: SizedBox.shrink());
    return Scaffold(
      body: _Main(
        label: 'Account',
        child: Semantics(
          container: true,
          label: 'Signed in',
          child: const Text('Account'),
        ),
      ),
    );
  }
}

class _Main extends StatelessWidget {
  const _Main({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        role: SemanticsRole.main,
        container: true,
        explicitChildNodes: true,
        label: label,
        child: child,
      ),
    );
  }
}

Future<String?> _login(String username, String password) async {
  if (_apiOrigin.isEmpty) return null;
  final response = await http.post(
    Uri.parse('$_apiOrigin/login'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'username': username, 'password': password}),
  );
  if (response.statusCode != 200) return null;
  final Object? decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) return null;
  final token = decoded['token'];
  if (token is! String || token.isEmpty) return null;
  return token;
}

String? _readToken() {
  final value = web.window.localStorage.getItem(_tokenKey);
  if (value == null || value.isEmpty) return null;
  return value;
}

void _writeToken(String token) {
  web.window.localStorage.setItem(_tokenKey, token);
}

void _clearToken() {
  web.window.localStorage.removeItem(_tokenKey);
}
