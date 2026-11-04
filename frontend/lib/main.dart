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
      title: 'BC Super App — Enterprise Chat & Cloud Vault',
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
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppTheme.motionMed,
            curve: AppTheme.motionCurve,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: child,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    boxShadow: AppTheme.glow(AppTheme.brandEmerald),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'BC',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: AppTheme.brandEmerald,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'กำลังซิงค์ข้อมูลแชทองค์กรและคลังไฟล์ถาวร...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
