import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/demo_repository.dart';
import '../core/app_logger.dart';
import 'diagnostics_screen.dart';
import 'reon_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.repository});

  final DemoVodovodRepository repository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool isAutoLogin = false;
  String appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _restoreSession();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final saved = await widget.repository.loadSavedLogin();
    if (!mounted || saved == null) return;
    usernameController.text = saved.username;
    passwordController.text = saved.password;
    await submit(auto: true);
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => appVersion = info.version);
  }

  Future<void> submit({bool auto = false}) async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
      isAutoLogin = auto;
    });
    try {
      final user = await widget.repository.login(
        usernameController.text,
        passwordController.text,
      );
      await widget.repository.rememberLogin(
        usernameController.text,
        passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReonScreen(repository: widget.repository, user: user),
        ),
      );
    } catch (error, stack) {
      unawaited(AppLogger.error('Prijava nije uspjela', error, stack));
      if (!mounted) return;
      if (!auto) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isAutoLogin = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.water_drop_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'VOB Ocitavanje',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isAutoLogin
                        ? 'Nastavljam prijavu...'
                        : 'Terenska očitavanja',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: usernameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Korisničko ime',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      labelText: 'Lozinka',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: isLoading ? null : submit,
                    icon: isLoading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Prijavi se'),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Powered by ZP${appVersion.isEmpty ? '' : ' V: $appVersion'}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Center(
                    child: IconButton(
                      tooltip: 'Greške i dijagnostika',
                      icon: const Icon(Icons.bug_report_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DiagnosticsScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
