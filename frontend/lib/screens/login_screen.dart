import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final ValueChanged<AppUser> onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

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
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
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
                          color: AppTheme.softEmerald,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.g_mobiledata_rounded,
                          color: AppTheme.deepEmerald,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('ยกเลิก'),
                      ),
                      const SizedBox(width: 10),
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 900;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF071318),
              Color(0xFF0F172A),
              Color(0xFF0A2E1F),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 11, child: _buildHeroShowcase()),
                          const SizedBox(width: 40),
                          Expanded(flex: 10, child: _buildLoginCard()),
                        ],
                      )
                    : Column(
                        children: [
                          _buildCompactHeroHeader(),
                          const SizedBox(height: 24),
                          _buildLoginCard(),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeroHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.lineEmerald,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.lineEmerald.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'BC',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'BC Super App',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'แชทคุ้นเคยเหมือน LINE 100% · ไฟล์ไม่หมดอายุ · ซิงค์ข้ามเครื่องด้วย Gmail',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
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
        'Super App Mini-Apps (WebView + LINE Flex Card)',
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
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.lineEmerald,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.lineEmerald.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'BC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'BC Super App',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.lineEmerald.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.lineEmerald.withValues(alpha: 0.5),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'LINE Experience + Enterprise Cloud',
                        style: TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'แพลตฟอร์มสื่อสารและระบบเสริมองค์กรยุคใหม่ ใช้งานง่ายเหมือน LINE 100%',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 28),
        ...features.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.09),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.lineEmerald.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
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
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$3,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12.5,
                            height: 1.35,
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

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.softEmerald,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: AppTheme.lineEmerald,
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
                      ),
                    ),
                    Text(
                      'ไม่ต้องจำรหัสผ่าน ซิงค์ประวัติแชทและไฟล์อัตโนมัติ',
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

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(14),
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
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'เข้าสู่ระบบด้วยบัญชี Gmail (Google Sign-In)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'หรือกรอก Gmail เข้าใช้งานทันที',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.slateMuted.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 14),

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
            height: 44,
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

          const SizedBox(height: 20),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 18,
                color: AppTheme.lineEmerald,
              ),
              SizedBox(width: 6),
              Text(
                'Quick Demo Login (คลิกเดียวสลับบัญชีทดสอบ)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          ..._demoAccounts.map((acc) {
            final email = acc['email']!;
            final name = acc['name']!;
            final role = acc['role']!;
            final desc = acc['desc']!;
            final isAdmin = role.contains('Admin');

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isLoading
                    ? null
                    : () {
                        _emailController.text = email;
                        _nameController.text = name;
                        _performLogin(email: email, displayName: name);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      UserAvatar(
                        name: name,
                        radius: 19,
                        showOnline: true,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                PillBadge(
                                  text: role,
                                  backgroundColor: isAdmin
                                      ? AppTheme.softEmerald
                                      : const Color(0xFFE0E7FF),
                                  textColor: isAdmin
                                      ? AppTheme.deepEmerald
                                      : AppTheme.workBlue,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$email · $desc',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.slateMuted,
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
            );
          }),
        ],
      ),
    );
  }
}
