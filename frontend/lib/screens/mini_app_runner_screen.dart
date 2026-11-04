import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class MiniAppRunnerScreen extends StatefulWidget {
  final MiniAppItem miniApp;
  final List<Conversation> conversations;
  final String? initialConversationId;
  final ValueChanged<ChatMessage>? onCardSent;

  const MiniAppRunnerScreen({
    super.key,
    required this.miniApp,
    required this.conversations,
    this.initialConversationId,
    this.onCardSent,
  });

  @override
  State<MiniAppRunnerScreen> createState() => _MiniAppRunnerScreenState();
}

class _MiniAppRunnerScreenState extends State<MiniAppRunnerScreen> {
  late TextEditingController _field1Ctrl;
  late TextEditingController _field2Ctrl;
  late TextEditingController _field3Ctrl;
  late TextEditingController _noteCtrl;

  late String _label1;
  late String _label2;
  late String _label3;
  late String _statusBadge;

  String? _selectedConversationId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _selectedConversationId =
        widget.initialConversationId ??
        (widget.conversations.isNotEmpty
            ? widget.conversations.first.id
            : null);
    _initTemplateFields();
  }

  void _initTemplateFields() {
    final code = widget.miniApp.code.toLowerCase();
    if (code.contains('leave')) {
      _label1 = 'ประเภทการลา';
      _label2 = 'ช่วงวันที่ลา';
      _label3 = 'จำนวนวัน / ผู้อนุมัติ';
      _statusBadge = 'รออนุมัติใบลา';
      _field1Ctrl = TextEditingController(text: 'ลาพักร้อนประจำปี');
      _field2Ctrl = TextEditingController(text: '18 - 19 พ.ย. 2569');
      _field3Ctrl = TextEditingController(text: '2 วัน (อนุมัติโดย ลุงจืด)');
      _noteCtrl = TextEditingController(
        text: 'ฝากสมชายช่วยดูแลลูกค้าช่วงวันที่ไม่อยู่ครับ',
      );
    } else if (code.contains('quote')) {
      _label1 = 'ชื่อลูกค้า / บริษัท';
      _label2 = 'รายการเสนอราคา';
      _label3 = 'ยอดรวมสุทธิ (รวม VAT)';
      _statusBadge = 'ใบเสนอราคาด่วน';
      _field1Ctrl = TextEditingController(
        text: 'บจก. สยามโมเดิร์น เทรดดิ้ง',
      );
      _field2Ctrl = TextEditingController(
        text: 'ชุดซอฟต์แวร์ BC Account + Cloud 1 ปี',
      );
      _field3Ctrl = TextEditingController(text: '48,500.00 บาท');
      _noteCtrl = TextEditingController(
        text: 'ยืนราคา 30 วัน พร้อมติดตั้งและอบรมฟรี',
      );
    } else if (code.contains('expense')) {
      _label1 = 'รายการเบิกค่าใช้จ่าย';
      _label2 = 'เลขที่เอกสาร / ใบเสร็จ';
      _label3 = 'ยอดเงินขอเบิกสุทธิ';
      _statusBadge = 'รอฝ่ายบัญชีตรวจสอบ';
      _field1Ctrl = TextEditingController(
        text: 'ค่าเดินทางและน้ำมันพบลูกค้าโครงการเหนือ',
      );
      _field2Ctrl = TextEditingController(text: 'EXP-202611-089');
      _field3Ctrl = TextEditingController(text: '2,850.00 บาท');
      _noteCtrl = TextEditingController(
        text: 'แนบสลิปและใบกำกับภาษีในคลังไฟล์ถาวรเรียบร้อยแล้ว',
      );
    } else if (code.contains('book') || code.contains('meet')) {
      _label1 = 'หัวข้อนัดหมาย / ประชุม';
      _label2 = 'วันและเวลานัดหมาย';
      _label3 = 'สถานที่ / ห้องประชุม';
      _statusBadge = 'ยืนยันนัดหมาย';
      _field1Ctrl = TextEditingController(
        text: 'ประชุมวางแผนยอดขายไตรมาส 4',
      );
      _field2Ctrl = TextEditingController(text: 'พรุ่งนี้ เวลา 14:00 - 15:30 น.');
      _field3Ctrl = TextEditingController(
        text: 'ห้องประชุมใหญ่ ชั้น 3 / BC Meet',
      );
      _noteCtrl = TextEditingController(
        text: 'เตรียมรายงานสรุปยอดขายและรายการลูกค้าองค์กร',
      );
    } else {
      _label1 = 'หัวข้อรายการ (${widget.miniApp.title})';
      _label2 = 'รายละเอียดหลัก';
      _label3 = 'สถานะ / มูลค่ารายการ';
      _statusBadge = 'บริการเสริม Super App';
      _field1Ctrl = TextEditingController(
        text: 'รายการใหม่จาก ${widget.miniApp.title}',
      );
      _field2Ctrl = TextEditingController(text: widget.miniApp.subtitle);
      _field3Ctrl = TextEditingController(text: 'ดำเนินการเรียบร้อย');
      _noteCtrl = TextEditingController(
        text: 'สร้างผ่านระบบเสริม WebView Bridge ของ BC Super App',
      );
    }
  }

  @override
  void dispose() {
    _field1Ctrl.dispose();
    _field2Ctrl.dispose();
    _field3Ctrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildFlexPayload() {
    final user = ApiService.instance.currentUser;
    return {
      'app_code': widget.miniApp.code,
      'app_title': widget.miniApp.title,
      'category': widget.miniApp.category,
      'color': widget.miniApp.color,
      'icon': widget.miniApp.icon,
      'badge': _statusBadge,
      'title': _field1Ctrl.text.trim(),
      'subtitle': _field2Ctrl.text.trim(),
      'highlight': _field3Ctrl.text.trim(),
      'note': _noteCtrl.text.trim(),
      'fields': [
        {'label': _label1, 'value': _field1Ctrl.text.trim()},
        {'label': _label2, 'value': _field2Ctrl.text.trim()},
        {'label': _label3, 'value': _field3Ctrl.text.trim()},
      ],
      'submitted_by': user?.displayName ?? 'ผู้ใช้งาน',
      'submitted_email': user?.email ?? '',
      'external_url': ApiService.instance.resolveMiniAppUrl(widget.miniApp),
    };
  }

  Future<void> _openExternalWebView() async {
    final url = ApiService.instance.resolveMiniAppUrl(widget.miniApp);
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendFlexCardToChat() async {
    final targetId = _selectedConversationId;
    if (targetId == null || targetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกห้องแชทปลายทางก่อนส่งการ์ด')),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final payload = _buildFlexPayload();
      final msg = await ApiService.instance.sendMessage(
        targetId,
        type: 'flex_card',
        content: '${widget.miniApp.title}: ${_field1Ctrl.text.trim()}',
        flexPayload: payload,
      );
      if (!mounted) return;
      widget.onCardSent?.call(msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.deepEmerald,
          content: Text(
            'ส่งการ์ด "${widget.miniApp.title}" เข้าห้องแชทเรียบร้อยแล้ว',
          ),
        ),
      );
      Navigator.of(context).pop(msg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.dangerRed,
          content: Text('ส่งการ์ดไม่สำเร็จ: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = AppTheme.parseHexColor(widget.miniApp.color);
    final user = ApiService.instance.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: AppTheme.slateDark,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppTheme.resolveMiniAppIcon(widget.miniApp.icon),
                color: Colors.white,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.miniApp.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Mini-App WebView Bridge · หมวด ${widget.miniApp.category}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _openExternalWebView,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text(
                  'เปิด WebView เต็มจอ',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // SSO Status Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.softEmerald,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.lineEmerald.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        color: AppTheme.deepEmerald,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'เชื่อมต่อ SSO ด้วยบัญชี Gmail: ${user?.email ?? "-"} (${user?.displayName ?? "-"}) เรียบร้อยแล้ว',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.deepEmerald,
                          ),
                        ),
                      ),
                      PillBadge(
                        text: 'JS Bridge Active',
                        backgroundColor: Colors.white,
                        textColor: AppTheme.deepEmerald,
                        icon: Icons.check_circle_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final isWide = constraints.maxWidth >= 680;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: _buildFormCard(accentColor)),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 5,
                            child: _buildFlexPreviewCard(accentColor),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildFormCard(accentColor),
                        const SizedBox(height: 18),
                        _buildFlexPreviewCard(accentColor),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.edit_document, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'กรอกข้อมูล ${widget.miniApp.title}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            _label1,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.slateBody,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _field1Ctrl,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          Text(
            _label2,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.slateBody,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _field2Ctrl,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          Text(
            _label3,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.slateBody,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _field3Ctrl,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          const Text(
            'หมายเหตุเพิ่มเติม',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.slateBody,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),

          const Text(
            'เลือกห้องแชทปลายทางที่ต้องการส่งการ์ด (LINE Flex Message)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 6),
          if (widget.conversations.isEmpty)
            const Text(
              'ยังไม่มีห้องแชท กรุณาเปิดห้องแชทก่อน',
              style: TextStyle(fontSize: 13, color: AppTheme.dangerRed),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedConversationId,
              items: widget.conversations.map((conv) {
                return DropdownMenuItem<String>(
                  value: conv.id,
                  child: Text(
                    '${conv.name} (${conv.folderLabel})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedConversationId = val),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.forum_outlined, size: 18),
              ),
            ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : _sendFlexCardToChat,
              style: ElevatedButton.styleFrom(backgroundColor: accentColor),
              icon: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text(
                'ส่งการ์ดเข้าห้องแชท (LINE Flex Card)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlexPreviewCard(Color accentColor) {
    final user = ApiService.instance.currentUser;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF8CABD9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.visibility_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'ตัวอย่างการ์ดที่จะแสดงในห้องแชท (Flex Message)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Simulated LINE Flex Card Bubble
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  color: accentColor,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        AppTheme.resolveMiniAppIcon(widget.miniApp.icon),
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.miniApp.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _field1Ctrl.text.isEmpty ? '-' : _field1Ctrl.text,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _field2Ctrl.text.isEmpty ? '-' : _field2Ctrl.text,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.slateBody,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _label3,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _field3Ctrl.text.isEmpty
                                    ? '-'
                                    : _field3Ctrl.text,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_noteCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'หมายเหตุ: ${_noteCtrl.text.trim()}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                      const Divider(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.account_circle_outlined,
                            size: 15,
                            color: AppTheme.slateMuted,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'ผู้ส่ง: ${user?.displayName ?? "คุณ"}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ),
                          Text(
                            'เปิดดูรายละเอียด >',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ],
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
