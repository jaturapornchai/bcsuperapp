import 'dart:io' show Platform, Process, ProcessStartMode;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final ValueChanged<AppUser> onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

  /// Seeded by backend/src/seed.rs (TEST_ACCOUNTS); all five share the
  /// group room "ห้องทดสอบแชท 5 คน" with BC AI.
  static const List<({String email, String name})> testAccounts = [
    (email: 'tester1@bcapp.local', name: 'ก้อง (ทดสอบ 1)'),
    (email: 'tester2@bcapp.local', name: 'แพร (ทดสอบ 2)'),
    (email: 'tester3@bcapp.local', name: 'บอส (ทดสอบ 3)'),
    (email: 'tester4@bcapp.local', name: 'มายด์ (ทดสอบ 4)'),
    (email: 'tester5@bcapp.local', name: 'ต้น (ทดสอบ 5)'),
  ];

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController(
    text: 'jead@bcapp.local',
  );
  final TextEditingController _nameController = TextEditingController(
    text: 'ลุงจืด (Super Admin)',
  );

  bool _isLoading = false;
  String? _errorMessage;

  static const List<Map<String, String>> _demoAccounts = [
    {
      'email': 'jead@bcapp.local',
      'name': 'ลุงจืด (Super Admin)',
      'role': 'Super Admin',
      'desc': 'สิทธิ์ผู้ดูแลระบบสูงสุด + จัดการ Mini-App หลังบ้าน',
    },
    {
      'email': 'somchai.sales@bcapp.local',
      'name': 'สมชาย ฝ่ายขาย',
      'role': 'ฝ่ายขาย',
      'desc': 'ทดสอบส่งใบเสนอราคา รูปหน้างาน และแชทกลุ่มขาย',
    },
    {
      'email': 'nida.acc@bcapp.local',
      'name': 'นิดา บัญชีการเงิน',
      'role': 'ฝ่ายบัญชี',
      'desc': 'ทดสอบตรวจเอกสารเบิกจ่าย คลังไฟล์ถาวร และ BC Keep',
    },
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _performLogin({
    required String email,
    required String displayName,
  }) async {
    if (email.trim().isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกอีเมล Gmail ก่อนเข้าสู่ระบบ');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = await ApiService.instance.loginWithGoogle(
        email: email.trim(),
        displayName: displayName.trim().isEmpty
            ? email.split('@').first
            : displayName.trim(),
      );
      if (!mounted) return;
      widget.onLoggedIn(user);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showGoogleAccountModal() async {
    final emailCtrl = TextEditingController(text: _emailController.text);
    final nameCtrl = TextEditingController(text: _nameController.text);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.brandSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.g_mobiledata_rounded,
                          color: AppTheme.brandDeep,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'เข้าสู่ระบบด้วยบัญชี Google (Gmail)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'ซิงค์แชทและไฟล์ถาวรข้ามเครื่องอัตโนมัติ 100%',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'อีเมล Gmail ของคุณ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateBody,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'เช่น yourname@example.com',
                      prefixIcon: Icon(Icons.mail_outline_rounded, size: 19),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'ชื่อที่ใช้แสดงในแชท (Display Name)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateBody,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'เช่น คุณสมศักดิ์ ฝ่ายบริหาร',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('ยกเลิก'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          final email = emailCtrl.text.trim();
                          final name = nameCtrl.text.trim();
                          Navigator.of(ctx).pop();
                          _emailController.text = email;
                          _nameController.text = name;
                          _performLogin(email: email, displayName: name);
                        },
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('ยืนยันเข้าสู่ระบบด้วย Gmail'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Fade + slide in once; delay staggers hero and card.
  Widget _enter({required Widget child, int delayMs = 0}) {
    final total = 400 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: AppTheme.motionCurve),
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF071318), Color(0xFF0F172A), Color(0xFF0A2E1F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Soft radial emerald glow behind the hero.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: isWide
                          ? const Alignment(-0.6, -0.3)
                          : const Alignment(0, -0.8),
                      radius: 0.9,
                      colors: [
                        AppTheme.brandPrimary.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 32 : 16,
                    vertical: isWide ? 32 : 20,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 1120 : 480),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 11,
                                child: _enter(child: _buildHeroShowcase()),
                              ),
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 10,
                                child: _enter(
                                  delayMs: 120,
                                  child: _buildLoginCard(wide: true),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _enter(child: _buildCompactHeroHeader()),
                              const SizedBox(height: 20),
                              _enter(
                                delayMs: 120,
                                child: _buildLoginCard(wide: false),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoTile(double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: AppTheme.glow(AppTheme.brandPrimary),
      ),
      alignment: Alignment.center,
      child: Text(
        'BC',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildCompactHeroHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _logoTile(52, 21),
        const SizedBox(width: 14),
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BC Super App',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              Text(
                'แชทใช้งานง่าย · ไฟล์ไม่หมดอายุ · ซิงค์ข้ามเครื่องด้วย Gmail',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroShowcase() {
    const features = [
      (
        Icons.cloud_done_rounded,
        'ไฟล์และรูปภาพไม่หมดอายุ (MinIO Permanent Vault)',
        'เก็บไฟล์เอกสาร รูปหน้างาน และใบเสนอราคาถาวรบน MinIO เปิดย้อนหลังได้ตลอดชีพ',
      ),
      (
        Icons.sync_lock_rounded,
        'ซิงค์แชทข้ามเครื่อง 100% ด้วยบัญชี Gmail',
        'ล็อกอินเครื่องใหม่หรือเปิดบนเว็บ/มือถือ ประวัติแชทและ Keep มาครบทันทีไม่ต้องสำรองเอง',
      ),
      (
        Icons.folder_special_rounded,
        'แยกหมวดแชทเรื่องงาน / ส่วนตัว / กลุ่ม / ปักหมุด',
        'แก้ปัญหาแชทงานปนแชทส่วนตัว พร้อมแถบปักหมุดประกาศสำคัญบนหัวห้องแชท',
      ),
      (
        Icons.dashboard_customize_rounded,
        'ระบบเสริม Mini-App (WebView + การ์ด Flex Card)',
        'เปิดระบบใบลา ใบเสนอราคา เบิกค่าใช้จ่าย ส่งเป็นการ์ดเข้าห้องแชท เพิ่มบริการใหม่จากหลังบ้านได้ทันที',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _logoTile(58, 23),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'BC Super App',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.brandPrimary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.brandPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                        // widthFactor keeps the pill hugging its label
                        // instead of stretching across the hero column.
                        child: const Center(
                          widthFactor: 1,
                          child: Text(
                            'Enterprise Chat + Cloud Vault',
                            style: TextStyle(
                              color: Color(0xFF4ADE80),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'แพลตฟอร์มสื่อสารและระบบเสริมองค์กรยุคใหม่ ใช้งานง่าย คุ้นมือตั้งแต่ครั้งแรก',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        ...features.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Icon(
                      item.$1,
                      color: const Color(0xFF4ADE80),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$3,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard({required bool wide}) {
    return Container(
      padding: EdgeInsets.all(wide ? 32 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        boxShadow: AppTheme.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  color: AppTheme.brandPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เข้าสู่ระบบด้วยบัญชี Gmail',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateDark,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      'ไม่ต้องจำรหัสผ่าน ซิงค์ประวัติแชทและไฟล์อัตโนมัติ',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.slateMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppTheme.dangerRed,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.dangerRed,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Primary Google Sign-In Button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _showGoogleAccountModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.slateDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFFEA4335),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'เข้าสู่ระบบด้วย Google (Gmail)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(child: Divider(height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'หรือกรอก Gmail เข้าใช้งานทันที',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AppTheme.slateMuted.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const Expanded(child: Divider(height: 1)),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'บัญชี Gmail / อีเมลองค์กร',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'ชื่อที่แสดงในห้องแชท',
              prefixIcon: Icon(Icons.badge_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _performLogin(
                      email: _emailController.text,
                      displayName: _nameController.text,
                    ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                _isLoading
                    ? 'กำลังซิงค์ข้อมูลแชท...'
                    : 'เข้าสู่ระบบ BC Super App',
              ),
            ),
          ),

          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: AppTheme.brandPrimary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Quick Demo Login (คลิกเดียวสลับบัญชีทดสอบ)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          ..._demoAccounts.map((acc) {
            final email = acc['email']!;
            final name = acc['name']!;
            final role = acc['role']!;
            return _DemoAccountTile(
              name: name,
              role: role,
              email: email,
              desc: acc['desc']!,
              onTap: _isLoading
                  ? null
                  : () {
                      _emailController.text = email;
                      _nameController.text = name;
                      _performLogin(email: email, displayName: name);
                    },
            );
          }),
          const SizedBox(height: 22),
          _buildTestChatSection(),
        ],
      ),
    );
  }

  // Only the desktop exe can relaunch itself as extra windows.
  bool get _canOpenTestWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _openTestChatWindows() async {
    try {
      for (var i = 0; i < LoginScreen.testAccounts.length; i++) {
        await Process.start(Platform.resolvedExecutable, [
          '--test-login=${LoginScreen.testAccounts[i].email}',
          '--test-slot=$i',
        ], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เปิดหน้าต่างทดสอบไม่สำเร็จ: $e');
    }
  }

  Widget _buildTestChatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.groups_rounded, size: 18, color: AppTheme.brandPrimary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'ทดสอบแชท 5 คน (บัญชีทดสอบ)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'ทั้ง 5 คนอยู่ใน "ห้องทดสอบแชท 5 คน" พร้อม BC AI ลองส่งข้อความ รูป ไฟล์ และพิมพ์ @ai ได้เลย',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.slateMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        if (_canOpenTestWindows) ...[
          FilledButton.icon(
            onPressed: _isLoading ? null : _openTestChatWindows,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('เปิด 5 หน้าต่าง คุยกันได้ทันที'),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final acc in LoginScreen.testAccounts)
              ActionChip(
                avatar: const Icon(Icons.person_rounded, size: 16),
                label: Text(acc.name),
                onPressed: _isLoading
                    ? null
                    : () {
                        _emailController.text = acc.email;
                        _nameController.text = acc.name;
                        _performLogin(email: acc.email, displayName: acc.name);
                      },
              ),
          ],
        ),
      ],
    );
  }
}

class _DemoAccountTile extends StatefulWidget {
  final String name;
  final String role;
  final String email;
  final String desc;
  final VoidCallback? onTap;

  const _DemoAccountTile({
    required this.name,
    required this.role,
    required this.email,
    required this.desc,
    required this.onTap,
  });

  @override
  State<_DemoAccountTile> createState() => _DemoAccountTileState();
}

class _DemoAccountTileState extends State<_DemoAccountTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role.contains('Admin');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AppTheme.motionFast,
          curve: AppTheme.motionCurve,
          decoration: BoxDecoration(
            color: _hover ? AppTheme.brandSoft : AppTheme.surfaceBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: _hover
                  ? AppTheme.brandPrimary.withValues(alpha: 0.5)
                  : AppTheme.borderSubtle,
            ),
            boxShadow: _hover ? AppTheme.shadowSm : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    UserAvatar(name: widget.name, radius: 19, showOnline: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.slateDark,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              PillBadge(
                                text: widget.role,
                                backgroundColor: isAdmin
                                    ? AppTheme.brandSoft
                                    : const Color(0xFFE0E7FF),
                                textColor: isAdmin
                                    ? AppTheme.brandDeep
                                    : AppTheme.workBlue,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.email} · ${widget.desc}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.slateMuted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.slateMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
