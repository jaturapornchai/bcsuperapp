import 'package:flutter/material.dart';

import 'models/models.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BCApp());
}

typedef MyApp = BCApp;

class BCApp extends StatefulWidget {
  const BCApp({super.key});

  @override
  State<BCApp> createState() => _BCAppState();
}

class _BCAppState extends State<BCApp> {
  bool _checkingSession = true;
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    try {
      final ok = await ApiService.instance.restoreSession();
      if (!mounted) return;
      setState(() {
        _currentUser = ok ? ApiService.instance.currentUser : null;
        _checkingSession = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingSession = false);
    }
  }

  void _handleLoggedIn(AppUser user) {
    setState(() => _currentUser = user);
  }

  Future<void> _handleLoggedOut() async {
    await ApiService.instance.logout();
    if (!mounted) return;
    setState(() => _currentUser = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BC Super App — LINE Enterprise & Cloud Vault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(),
      home: _checkingSession
          ? const _SplashLoadingView()
          : _currentUser == null
          ? LoginScreen(onLoggedIn: _handleLoggedIn)
          : MainShell(
              currentUser: _currentUser!,
              onLoggedOut: _handleLoggedOut,
              onUserChanged: (updated) =>
                  setState(() => _currentUser = updated),
            ),
    );
  }
}

class _SplashLoadingView extends StatelessWidget {
  const _SplashLoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slateDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppTheme.lineEmerald,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Text(
                'BC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: AppTheme.lineEmerald),
            const SizedBox(height: 12),
            const Text(
              'กำลังซิงค์ข้อมูลแชทองค์กรและคลังไฟล์ถาวร...',
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
