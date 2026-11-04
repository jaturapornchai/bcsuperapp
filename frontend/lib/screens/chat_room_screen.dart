import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'mini_app_runner_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final Conversation conversation;
  final List<Conversation> allConversations;
  final List<MiniAppItem> miniApps;
  final bool isEmbedded;
  final VoidCallback? onConversationUpdated;
  final ValueChanged<ChatRoomThemeMode>? onThemeChanged;

  const ChatRoomScreen({
    super.key,
    required this.conversation,
    required this.allConversations,
    required this.miniApps,
    this.isEmbedded = false,
    this.onConversationUpdated,
    this.onThemeChanged,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final TextEditingController _roomSearchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  late Conversation _conversation;
  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isUploading = false;
  bool _showStickerPicker = false;
  bool _showSearchBar = false;
  bool _isConfidentialMode = false;
  bool _showSecurityWatermark = true;
  final Set<String> _revealedMessageIds = <String>{};
  String _searchQuery = '';
  ChatMessage? _replyingTo;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  static const List<Map<String, String>> _thaiStickers = [
    {'code': 'ok_boss', 'emoji': '🫡✨', 'label': 'รับทราบครับลุงจืด!'},
    {'code': 'thank_you', 'emoji': '🙏💚', 'label': 'ขอบคุณมากๆ ครับ'},
    {'code': 'done_work', 'emoji': '✅🚀', 'label': 'ส่งงานเรียบร้อย!'},
    {'code': 'approved', 'emoji': '👍💯', 'label': 'อนุมัติดำเนินการเลย'},
    {'code': 'fighting', 'emoji': '✌️🔥', 'label': 'สู้ๆ ครับทีมงาน BC'},
    {'code': 'urgent', 'emoji': '⚡📄', 'label': 'กำลังตรวจเอกสารด่วน'},
    {'code': 'meeting', 'emoji': '📅☕', 'label': 'พร้อมเข้าประชุมครับ'},
    {'code': 'celebrate', 'emoji': '🎉🏆', 'label': 'ปิดยอดขายสำเร็จ!'},
  ];

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _loadRoomData();
    _wsSub = ApiService.instance.wsEvents.listen(_handleWsEvent);
  }

  @override
  void didUpdateWidget(covariant ChatRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _conversation = widget.conversation;
      _replyingTo = null;
      _showStickerPicker = false;
      _showSearchBar = false;
      _searchQuery = '';
      _roomSearchCtrl.clear();
      _loadRoomData();
    } else {
      _conversation = widget.conversation;
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _msgCtrl.dispose();
    _roomSearchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? event['event'] ?? '').toString();
    final convId =
        (event['conversation_id'] ??
                (event['message'] is Map
                    ? event['message']['conversation_id']
                    : null) ??
                '')
            .toString();

    if (convId == _conversation.id ||
        type == 'message_new' ||
        type == 'message_read' ||
        type == 'message_unsend' ||
        type == 'message_deleted' ||
        type == 'conversation_updated') {
      _refreshMessagesQuietly();
    }
  }

  Future<void> _loadRoomData() async {
    setState(() => _isLoading = true);
    try {
      final msgs = await ApiService.instance.fetchMessages(_conversation.id);
      await ApiService.instance.markConversationRead(_conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshMessagesQuietly() async {
    try {
      final msgs = await ApiService.instance.fetchMessages(_conversation.id);
      await ApiService.instance.markConversationRead(_conversation.id);
      if (!mounted) return;
      setState(() => _messages = msgs);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendTextMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final replyId = _replyingTo?.id;
    final confidential = _isConfidentialMode;
    _msgCtrl.clear();
    setState(() => _replyingTo = null);

    try {
      final sent = await ApiService.instance.sendMessage(
        _conversation.id,
        type: 'text',
        content: text,
        replyToId: replyId,
        isConfidential: confidential,
      );
      if (!mounted) return;
      setState(() {
        if (confidential) _revealedMessageIds.add(sent.id);
        _messages = [..._messages, sent];
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งข้อความไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _sendSticker(Map<String, String> sticker) async {
    setState(() => _showStickerPicker = false);
    try {
      final sent = await ApiService.instance.sendMessage(
        _conversation.id,
        type: 'sticker',
        content: sticker['label']!,
        stickerCode: sticker['code']!,
        replyToId: _replyingTo?.id,
        isConfidential: _isConfidentialMode,
      );
      if (!mounted) return;
      setState(() {
        _replyingTo = null;
        _messages = [..._messages, sent];
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
    } catch (_) {}
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final picked = files.first;
      final bytes = await picked.readAsBytes();

      await _uploadBytesAndSend(
        fileName: picked.name,
        bytes: bytes,
        extension: picked.extension ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถเลือกไฟล์ได้: $e')),
      );
    }
  }

  Future<void> _uploadBytesAndSend({
    required String fileName,
    required List<int> bytes,
    required String extension,
  }) async {
    setState(() => _isUploading = true);
    try {
      final ext = extension.toLowerCase();
      String mimeType = 'application/octet-stream';
      if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        mimeType = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
      } else if (ext == 'pdf') {
        mimeType = 'application/pdf';
      } else if (ext == 'txt' || ext == 'csv') {
        mimeType = 'text/plain; charset=utf-8';
      }

      final b64 = base64Encode(bytes);
      final attachment = await ApiService.instance.uploadFileBase64(
        fileName: fileName,
        mimeType: mimeType,
        dataBase64: b64,
      );

      final msgType = attachment.isImage ? 'image' : 'file';
      final sent = await ApiService.instance.sendMessage(
        _conversation.id,
        type: msgType,
        content: fileName,
        attachment: attachment,
        replyToId: _replyingTo?.id,
        isConfidential: _isConfidentialMode,
      );

      if (!mounted) return;
      setState(() {
        _replyingTo = null;
        if (_isConfidentialMode) _revealedMessageIds.add(sent.id);
        _messages = [..._messages, sent];
      });
      _scrollToBottom();
      widget.onConversationUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.deepEmerald,
          content: Text(
            'อัปโหลด "$fileName" เก็บถาวรบน MinIO เรียบร้อย (ส่งผิดกดลบทำลายไฟล์ได้ทันที)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.dangerRed,
          content: Text('อัปโหลดไฟล์ไม่สำเร็จ: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _showAttachmentMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.softEmerald,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.cloud_upload_rounded,
                        color: AppTheme.deepEmerald,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ส่งรูปภาพ & ไฟล์เอกสารองค์กร (เก็บถาวรบน MinIO)',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          Text(
                            'ไฟล์ไม่หมดอายุ · รองรับโหมดความลับ · ส่งผิดสามารถกดลบทำลายไฟล์ได้ 100%',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: AppTheme.surfaceBg,
                  leading: const Icon(
                    Icons.folder_open_rounded,
                    color: AppTheme.lineEmerald,
                  ),
                  title: const Text(
                    'เลือกไฟล์หรือรูปภาพจากเครื่องของคุณ',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'รองรับ PNG, JPG, PDF, Excel, Word และเอกสารทุกชนิด',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadFile();
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: AppTheme.surfaceBg,
                  leading: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppTheme.workBlue,
                  ),
                  title: const Text(
                    'ส่งไฟล์ใบเสนอราคาตัวอย่างเข้า MinIO ทันที (Quick Demo File)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'สร้างไฟล์เอกสารทดสอบอัปโหลดเข้า Bucket bcapp-storage จริงทันที',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final sampleContent = utf8.encode(
                      'เอกสารลับเฉพาะองค์กร: ใบเสนอราคา BC Super App Enterprise\n'
                      'ลูกค้า: บจก. สยามโมเดิร์น เทรดดิ้ง\n'
                      'ยอดสุทธิ: 48,500.00 บาท (รวมภาษีมูลค่าเพิ่ม)\n'
                      'จัดเก็บถาวรบน MinIO Object Storage (ส่งผิดสามารถสั่งลบทำลายไฟล์ได้ทันที)\n',
                    );
                    _uploadBytesAndSend(
                      fileName:
                          'QT-BCApp-${DateTime.now().millisecondsSinceEpoch % 10000}.txt',
                      bytes: sampleContent,
                      extension: 'txt',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleFolderCategory() async {
    final nextFolder = _conversation.folder == 'work' ? 'personal' : 'work';
    final updated = await ApiService.instance.updateConversationMeta(
      _conversation.id,
      folder: nextFolder,
    );
    if (!mounted) return;
    setState(() {
      if (updated != null) {
        _conversation = updated;
      } else {
        _conversation = Conversation(
          id: _conversation.id,
          kind: _conversation.kind,
          name: _conversation.name,
          avatarUrl: _conversation.avatarUrl,
          folder: nextFolder,
          isPinned: _conversation.isPinned,
          memberIds: _conversation.memberIds,
          memberCount: _conversation.memberCount,
          unreadCount: _conversation.unreadCount,
          pinnedMessage: _conversation.pinnedMessage,
          lastMessage: _conversation.lastMessage,
          peerUser: _conversation.peerUser,
          updatedAt: _conversation.updatedAt,
        );
      }
    });
    widget.onConversationUpdated?.call();
  }

  Future<void> _togglePinRoom() async {
    final nextPin = !_conversation.isPinned;
    await ApiService.instance.updateConversationMeta(
      _conversation.id,
      isPinned: nextPin,
    );
    if (!mounted) return;
    setState(() {
      _conversation = Conversation(
        id: _conversation.id,
        kind: _conversation.kind,
        name: _conversation.name,
        avatarUrl: _conversation.avatarUrl,
        folder: _conversation.folder,
        isPinned: nextPin,
        memberIds: _conversation.memberIds,
        memberCount: _conversation.memberCount,
        unreadCount: _conversation.unreadCount,
        pinnedMessage: _conversation.pinnedMessage,
        lastMessage: _conversation.lastMessage,
        peerUser: _conversation.peerUser,
        updatedAt: _conversation.updatedAt,
      );
    });
    widget.onConversationUpdated?.call();
  }

  Future<void> _pinMessageToBanner(ChatMessage? msg) async {
    await ApiService.instance.pinConversationMessage(
      _conversation.id,
      msg?.id,
    );
    if (!mounted) return;
    setState(() {
      _conversation = Conversation(
        id: _conversation.id,
        kind: _conversation.kind,
        name: _conversation.name,
        avatarUrl: _conversation.avatarUrl,
        folder: _conversation.folder,
        isPinned: _conversation.isPinned,
        memberIds: _conversation.memberIds,
        memberCount: _conversation.memberCount,
        unreadCount: _conversation.unreadCount,
        pinnedMessage: msg,
        lastMessage: _conversation.lastMessage,
        peerUser: _conversation.peerUser,
        updatedAt: _conversation.updatedAt,
      );
    });
    widget.onConversationUpdated?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.slateDark,
        content: Text(
          msg != null
              ? 'ปักหมุดประกาศไว้บนหัวห้องแชทเรียบร้อยแล้ว'
              : 'ยกเลิกปักหมุดประกาศบนหัวห้องแชทแล้ว',
        ),
      ),
    );
  }

  Future<void> _saveMessageToKeep(ChatMessage msg) async {
    try {
      await ApiService.instance.createNote(
        conversationId: _conversation.id,
        title: 'จากห้อง ${_conversation.name} (${msg.senderName})',
        content: msg.cleanContent.isNotEmpty
            ? msg.cleanContent
            : msg.previewText,
        category: _conversation.isWork ? 'เรื่องงาน' : 'บันทึกสำคัญ',
        color: '#06C755',
        attachment: msg.attachment,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.deepEmerald,
          content: Text('บันทึกข้อความเข้า BC Keep & โน้ตประจำห้องเรียบร้อยแล้ว'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกเข้า Keep ไม่สำเร็จ: $e')),
      );
    }
  }

  /// Instant Recall / Unsend & Purge MinIO File ("ส่งผิดสามารถลบได้ทันที")
  Future<void> _unsendOrHardRecall(ChatMessage msg, {bool hard = false}) async {
    try {
      await ApiService.instance.unsendMessage(msg.id, hard: hard);
      if (!mounted) return;
      if (hard) {
        setState(() {
          _messages = _messages.where((m) => m.id != msg.id).toList();
        });
      }
      await _refreshMessagesQuietly();
      widget.onConversationUpdated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.dangerRed,
          content: Text(
            'ลบข้อความและทำลายไฟล์ออกจากเซิร์ฟเวอร์เรียบร้อยแล้ว',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบข้อความไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _openMiniAppPicker() async {
    if (widget.miniApps.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.widgets_rounded,
                      color: AppTheme.lineEmerald,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'เลือกบริการเสริม Super App เพื่อส่งการ์ดเข้าห้องนี้',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.miniApps.map((app) {
                    final color = AppTheme.parseHexColor(app.color);
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MiniAppRunnerScreen(
                              miniApp: app,
                              conversations: widget.allConversations,
                              initialConversationId: _conversation.id,
                              onCardSent: (_) {
                                _refreshMessagesQuietly();
                                widget.onConversationUpdated?.call();
                              },
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 160,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                AppTheme.resolveMiniAppIcon(app.icon),
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                app.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPermanentVaultDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RoomVaultDialog(conversation: _conversation),
    );
  }

  Future<void> _openAiSummarizeModal() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AiSummaryModal(
        conversation: _conversation,
        onSendToRoom: (formattedText) async {
          final sent = await ApiService.instance.sendMessage(
            _conversation.id,
            type: 'text',
            content: formattedText,
          );
          if (!mounted) return;
          setState(() => _messages = [..._messages, sent]);
          _scrollToBottom();
          widget.onConversationUpdated?.call();
        },
        onSaveToKeep: (formattedText) async {
          await ApiService.instance.createNote(
            conversationId: _conversation.id,
            title: '✨ AI สรุปห้อง ${_conversation.name}',
            content: formattedText,
            category: 'AI สรุปงาน',
            color: '#7C3AED',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.deepEmerald,
              content: Text('บันทึกผลสรุป AI เข้า BC Keep & โน้ตห้องเรียบร้อยแล้ว!'),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAiAssistModal({String initialMode = 'polite'}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AiWritingAssistModal(
        conversation: _conversation,
        initialDraft: _msgCtrl.text,
        initialMode: initialMode,
        onApplyToComposer: (text) {
          setState(() {
            _msgCtrl.text = text;
            _msgCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _msgCtrl.text.length),
            );
          });
        },
        onSendImmediately: (text) async {
          _msgCtrl.text = text;
          await _sendTextMessage();
        },
      ),
    );
  }

  void _insertAiMention() {
    final current = _msgCtrl.text;
    if (!current.startsWith('@ai ')) {
      setState(() {
        _msgCtrl.text = '@ai ${current.trimLeft()}';
        _msgCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _msgCtrl.text.length),
        );
      });
    }
  }

  List<ChatMessage> get _filteredMessages {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _messages;
    return _messages.where((m) {
      return m.content.toLowerCase().contains(q) ||
          m.senderName.toLowerCase().contains(q) ||
          (m.attachment?.fileName.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ApiService.instance.chatTheme;
    final currentUser = ApiService.instance.currentUser;
    final currentUserId = currentUser?.id ?? '';
    final isAdmin = currentUser?.isAdmin ?? false;
    final visibleMessages = _filteredMessages;

    return Scaffold(
      backgroundColor: themeMode.backgroundColor,
      body: Column(
        children: [
          _buildRoomHeader(themeMode),
          if (_showSearchBar) _buildInRoomSearchBar(),
          if (_conversation.pinnedMessage != null)
            _buildPinnedAnnouncementBanner(_conversation.pinnedMessage!),
          Expanded(
            child: Stack(
              children: [
                if (_showSecurityWatermark)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _buildEnterpriseWatermarkOverlay(
                        currentUser?.displayName ?? 'BC Enterprise User',
                        currentUser?.email ?? 'confidential@bcapp.local',
                        themeMode.isDark,
                      ),
                    ),
                  ),
                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : visibleMessages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'เริ่มส่งข้อความ เอกสารความลับ หรือไฟล์ถาวรในห้องแชทองค์กรนี้ได้เลย (ส่งผิดลบได้ 100%)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        itemCount: visibleMessages.length,
                        itemBuilder: (ctx, index) {
                          final msg = visibleMessages[index];
                          final isMe = msg.senderId == currentUserId;
                          return _buildMessageRow(
                            msg,
                            isMe,
                            isAdmin,
                            themeMode,
                          );
                        },
                      ),
              ],
            ),
          ),
          if (_showStickerPicker) _buildStickerPickerPanel(),
          if (_replyingTo != null) _buildReplyBanner(_replyingTo!),
          _buildComposerBar(),
        ],
      ),
    );
  }

  Widget _buildEnterpriseWatermarkOverlay(
    String userName,
    String email,
    bool isDark,
  ) {
    final text = 'CONFIDENTIAL · $userName ($email) · ห้ามถ่ายภาพหน้าจอ';
    final color = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : AppTheme.slateDark.withValues(alpha: 0.055);

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(4, (row) {
              return Transform.rotate(
                angle: -math.pi / 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(2, (col) {
                    return Text(
                      text,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    );
                  }),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildRoomHeader(ChatRoomThemeMode themeMode) {
    final isWork = _conversation.folder == 'work';
    final peerDept = _conversation.peerUser?.department ??
        (_conversation.isGroup ? 'กลุ่มงานองค์กร' : 'บริหาร/ปฏิบัติการ');

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppTheme.slateDark,
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!widget.isEmbedded) ...[
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: Colors.white,
              tooltip: 'ย้อนกลับ',
            ),
            const SizedBox(width: 4),
          ],
          UserAvatar(
            name: _conversation.name,
            avatarUrl: _conversation.avatarUrl,
            radius: 19,
            showOnline: !_conversation.isGroup,
            isOfficial: _conversation.isOfficial,
            isGroup: _conversation.isGroup,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _conversation.isGroup
                            ? '${_conversation.name} (${_conversation.memberCount})'
                            : _conversation.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PillBadge(
                      text: peerDept,
                      backgroundColor: const Color(0xFF334155),
                      textColor: const Color(0xFFE2E8F0),
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _toggleFolderCategory,
                      borderRadius: BorderRadius.circular(999),
                      child: PillBadge(
                        text: _conversation.folderLabel,
                        backgroundColor: isWork
                            ? AppTheme.workBlue.withValues(alpha: 0.25)
                            : AppTheme.lineEmerald.withValues(alpha: 0.22),
                        textColor: isWork
                            ? const Color(0xFF93C5FD)
                            : const Color(0xFF4ADE80),
                        icon: isWork
                            ? Icons.work_outline_rounded
                            : Icons.person_outline_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  '🔒 ห้องสนทนาองค์กร (Enterprise DLP) · ส่งผิดกดลบและทำลายไฟล์บนเซิร์ฟเวอร์ได้ทันที',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            onPressed: () => setState(
              () => _showSecurityWatermark = !_showSecurityWatermark,
            ),
            tooltip: _showSecurityWatermark
                ? 'เปิดลายน้ำนิรภัยป้องกันการแคปหน้าจออยู่'
                : 'เปิดลายน้ำนิรภัยองค์กร',
            icon: Icon(
              Icons.verified_user_rounded,
              size: 19,
              color: _showSecurityWatermark
                  ? AppTheme.lineEmerald
                  : const Color(0xFF94A3B8),
            ),
          ),
          IconButton(
            onPressed: _togglePinRoom,
            tooltip: _conversation.isPinned
                ? 'เลิกปักหมุดห้องแชท'
                : 'ปักหมุดห้องแชท',
            icon: Icon(
              _conversation.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              size: 19,
              color: _conversation.isPinned
                  ? AppTheme.goldPin
                  : const Color(0xFFCBD5E1),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  _searchQuery = '';
                  _roomSearchCtrl.clear();
                }
              });
            },
            tooltip: 'ค้นหาข้อความในห้องนี้',
            icon: Icon(
              Icons.search_rounded,
              size: 20,
              color: _showSearchBar
                  ? AppTheme.lineEmerald
                  : const Color(0xFFCBD5E1),
            ),
          ),
          PopupMenuButton<ChatRoomThemeMode>(
            tooltip: 'เปลี่ยนสีพื้นหลังห้องแชท',
            icon: const Icon(
              Icons.palette_outlined,
              size: 19,
              color: Color(0xFFCBD5E1),
            ),
            onSelected: (mode) async {
              await ApiService.instance.setChatTheme(mode);
              if (!mounted) return;
              setState(() {});
              widget.onThemeChanged?.call(mode);
            },
            itemBuilder: (ctx) => ChatRoomThemeMode.values.map((m) {
              return PopupMenuItem<ChatRoomThemeMode>(
                value: m,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: m.backgroundColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: m == themeMode
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: _openAiSummarizeModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.personalPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 15),
              label: const Text(
                '✨ AI สรุปแชท & แกะงาน',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: _openPermanentVaultDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lineEmerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.folder_copy_rounded, size: 15),
              label: const Text(
                'คลังรูป & ไฟล์ถาวร',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInRoomSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.slateNavy,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _roomSearchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(
                hintText: 'ค้นหาข้อความ ชื่อไฟล์ หรือชื่อผู้ส่งในห้องนี้...',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              setState(() {
                _showSearchBar = false;
                _searchQuery = '';
                _roomSearchCtrl.clear();
              });
            },
            child: const Text(
              'ปิด',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedAnnouncementBanner(ChatMessage pinned) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: AppTheme.warningAmber,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'ประกาศปักหมุดประจำห้อง',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warningAmber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'โดย ${pinned.senderName} (${pinned.senderDepartment})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
                Text(
                  pinned.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slateDark,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _pinMessageToBanner(null),
            tooltip: 'เอาประกาศปักหมุดออก',
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(
    ChatMessage msg,
    bool isMe,
    bool isAdmin,
    ChatRoomThemeMode themeMode,
  ) {
    if (msg.isUnsent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 14,
                  color: Color(0xFFFCA5A5),
                ),
                const SizedBox(width: 6),
                Text(
                  '${isMe ? "คุณ" : msg.senderName} ยกเลิกข้อความและทำลายไฟล์แล้ว',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final timeStr = formatThaiTime(msg.createdAt);
    final readLabel = _conversation.isGroup && msg.readCount > 1
        ? 'อ่านแล้ว ${msg.readCount}'
        : 'อ่านแล้ว';
    final canRecall = isMe || isAdmin;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: UserAvatar(
                name: msg.senderName,
                avatarUrl: msg.senderAvatar,
                radius: 17,
              ),
            ),
            const SizedBox(width: 8),
          ],

          if (isMe) ...[
            _buildMessageActionMenu(msg, canRecall),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick 1-click "ส่งผิดลบได้" button right beside own message
                InkWell(
                  onTap: () => _unsendOrHardRecall(msg, hard: false),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.undo_rounded,
                          size: 11,
                          color: Color(0xFFFECACA),
                        ),
                        SizedBox(width: 3),
                        Text(
                          'ส่งผิดลบได้',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFECACA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  readLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: themeMode.isDark
                        ? const Color(0xFF4ADE80)
                        : Colors.white,
                    height: 1.1,
                  ),
                ),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: themeMode.isDark
                        ? const Color(0xFF94A3B8)
                        : Colors.white.withValues(alpha: 0.92),
                    height: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],

          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 4,
                      right: 4,
                      bottom: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (!isMe) ...[
                          Text(
                            msg.senderName,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: themeMode.isDark
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        PillBadge(
                          text: msg.senderDepartment,
                          backgroundColor: Colors.white.withValues(alpha: 0.88),
                          textColor: AppTheme.slateDark,
                        ),
                        if (msg.isConfidential) ...[
                          const SizedBox(width: 5),
                          const PillBadge(
                            text: '🔒 ลับเฉพาะองค์กร',
                            backgroundColor: Color(0xFF7F1D1D),
                            textColor: Color(0xFFFECACA),
                          ),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onLongPress: () =>
                        _showMessageSheetActions(msg, canRecall),
                    child: msg.isConfidential
                        ? _buildConfidentialWrapper(msg, isMe)
                        : _buildBubbleContent(msg, isMe),
                  ),
                ],
              ),
            ),
          ),

          if (!isMe) ...[
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRecall)
                  InkWell(
                    onTap: () => _unsendOrHardRecall(msg, hard: true),
                    child: const Text(
                      'แอดมินสั่งลบ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFECACA),
                      ),
                    ),
                  ),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: themeMode.isDark
                        ? const Color(0xFF94A3B8)
                        : Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            _buildMessageActionMenu(msg, canRecall),
          ],
        ],
      ),
    );
  }

  /// Confidential Message Wrapper: blurred/hidden until tapped + watermarked with reader's identity
  Widget _buildConfidentialWrapper(ChatMessage msg, bool isMe) {
    final isRevealed = _revealedMessageIds.contains(msg.id);
    final currentUser = ApiService.instance.currentUser;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDC2626), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF991B1B),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: Color(0xFFFDE68A),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '🔒 ลับเฉพาะองค์กร — ห้ามส่งต่อหรือแคปหน้าจอ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isRevealed)
                  InkWell(
                    onTap: () =>
                        setState(() => _revealedMessageIds.remove(msg.id)),
                    child: const Text(
                      'ซ่อนข้อมูล',
                      style: TextStyle(
                        color: Color(0xFFFDE68A),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!isRevealed)
            InkWell(
              onTap: () => setState(() => _revealedMessageIds.add(msg.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.visibility_off_rounded,
                      color: Color(0xFF991B1B),
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'เนื้อหาความลับถูกซ่อนไว้เพื่อความปลอดภัย',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'แตะเพื่อเปิดดูข้อมูลความลับ (บันทึกชื่อผู้เปิดอ่าน: ${currentUser?.displayName ?? "คุณ"})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.dangerRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: _buildBubbleContent(msg, isMe),
                ),
                Positioned(
                  right: 10,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Text(
                      'เปิดอ่านโดย ${currentUser?.email ?? ""}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.dangerRed.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMessageActionMenu(ChatMessage msg, bool canRecall) {
    return PopupMenuButton<String>(
      tooltip: 'จัดการข้อความ / ส่งผิดลบได้',
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 16,
        color: Colors.white.withValues(alpha: 0.85),
      ),
      onSelected: (action) {
        if (action == 'reply') {
          setState(() => _replyingTo = msg);
        } else if (action == 'pin') {
          _pinMessageToBanner(msg);
        } else if (action == 'keep') {
          _saveMessageToKeep(msg);
        } else if (action == 'unsend') {
          _unsendOrHardRecall(msg, hard: false);
        } else if (action == 'hard_recall') {
          _unsendOrHardRecall(msg, hard: true);
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'reply',
          child: Row(
            children: [
              Icon(Icons.reply_rounded, size: 17),
              SizedBox(width: 8),
              Text('ตอบกลับข้อความ (Reply)', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                Icons.push_pin_rounded,
                size: 17,
                color: AppTheme.warningAmber,
              ),
              SizedBox(width: 8),
              Text('ปักหมุดประกาศบนหัวห้อง', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'keep',
          child: Row(
            children: [
              Icon(
                Icons.bookmark_add_rounded,
                size: 17,
                color: AppTheme.lineEmerald,
              ),
              SizedBox(width: 8),
              Text('บันทึกเข้า BC Keep ถาวร', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (canRecall) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'unsend',
            child: Row(
              children: [
                Icon(
                  Icons.undo_rounded,
                  size: 17,
                  color: AppTheme.dangerRed,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ยกเลิกข้อความ & ลบไฟล์ทันที (ส่งผิดลบได้ 100%)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.dangerRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'hard_recall',
            child: Row(
              children: [
                Icon(
                  Icons.delete_forever_rounded,
                  size: 18,
                  color: Color(0xFF991B1B),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ลบไร้ร่องรอย (Hard Recall)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showMessageSheetActions(ChatMessage msg, bool canRecall) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('ตอบกลับข้อความ (Reply)'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _replyingTo = msg);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.push_pin_rounded,
                  color: AppTheme.warningAmber,
                ),
                title: const Text('ปักหมุดเป็นประกาศบนหัวห้องแชท'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pinMessageToBanner(msg);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.bookmark_add_rounded,
                  color: AppTheme.lineEmerald,
                ),
                title: const Text('บันทึกเข้า BC Keep & โน้ตกลุ่มถาวร'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveMessageToKeep(msg);
                },
              ),
              if (canRecall) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.undo_rounded,
                    color: AppTheme.dangerRed,
                  ),
                  title: const Text(
                    'ยกเลิกข้อความ & ลบไฟล์ทันที (ส่งผิดลบได้ 100%)',
                    style: TextStyle(
                      color: AppTheme.dangerRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'ดึงข้อความกลับจากหน้าจอทุกคนและทำลายไฟล์ใน MinIO ทันที',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _unsendOrHardRecall(msg, hard: false);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_rounded,
                    color: Color(0xFF991B1B),
                  ),
                  title: const Text(
                    'ลบไร้ร่องรอย (Hard Recall)',
                    style: TextStyle(
                      color: Color(0xFF991B1B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'ลบออกจากประวัติห้องแชทและทำลายไฟล์บนเซิร์ฟเวอร์โดยไม่เหลือข้อความค้าง',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _unsendOrHardRecall(msg, hard: true);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBubbleContent(ChatMessage msg, bool isMe) {
    switch (msg.type) {
      case 'sticker':
        return _buildStickerBubble(msg);
      case 'image':
        return _buildImageBubble(msg, isMe);
      case 'file':
        return _buildFileBubble(msg, isMe);
      case 'flex_card':
        return _buildFlexCardBubble(msg);
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? AppTheme.sentBubble : AppTheme.receivedBubble,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 16 : 4),
              topRight: Radius.circular(isMe ? 4 : 16),
              bottomLeft: const Radius.circular(16),
              bottomRight: const Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.replyTo != null)
                _buildReplyQuoteInsideBubble(msg.replyTo!),
              SelectableText(
                msg.cleanContent,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.slateDark,
                  height: 1.38,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildReplyQuoteInsideBubble(ReplySummary reply) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: AppTheme.deepEmerald, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ตอบกลับ ${reply.senderName}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.deepEmerald,
            ),
          ),
          Text(
            reply.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppTheme.slateBody),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerBubble(ChatMessage msg) {
    final matched = _thaiStickers.firstWhere(
      (s) => s['code'] == msg.stickerCode,
      orElse: () => {'emoji': '💚✨', 'label': msg.cleanContent},
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            matched['emoji'] ?? '💚',
            style: const TextStyle(fontSize: 38),
          ),
          const SizedBox(height: 4),
          Text(
            msg.cleanContent.isNotEmpty
                ? msg.cleanContent
                : (matched['label'] ?? ''),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBubble(ChatMessage msg, bool isMe) {
    final url = msg.attachment?.url ?? '';
    final fileName = msg.attachment?.fileName ?? msg.cleanContent;

    return Container(
      decoration: BoxDecoration(
        color: isMe ? AppTheme.sentBubble : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url.isNotEmpty)
            InkWell(
              onTap: () => _showImagePreviewDialog(url, fileName),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  minWidth: 180,
                ),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    color: AppTheme.surfaceBg,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      size: 40,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_done_rounded,
                  size: 14,
                  color: AppTheme.deepEmerald,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '$fileName · เก็บถาวรบน MinIO (ไม่หมดอายุ)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.deepEmerald,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreviewDialog(String url, String title) {
    final user = ApiService.instance.currentUser;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$title · เปิดอ่านโดย ${user?.displayName ?? ""} (${user?.email ?? ""})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileBubble(ChatMessage msg, bool isMe) {
    final att = msg.attachment;
    final fileName = att?.fileName ?? msg.cleanContent;
    final sizeText = formatFileSize(att?.fileSize ?? 0);
    final url = att?.url ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.sentBubble : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.workBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insert_drive_file_rounded,
                  color: AppTheme.workBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          sizeText,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const PillBadge(
                          text: 'MinIO ไม่หมดอายุ',
                          backgroundColor: AppTheme.softEmerald,
                          textColor: AppTheme.deepEmerald,
                          icon: Icons.verified_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (url.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  tooltip: 'ดาวน์โหลด / เปิดไฟล์จาก MinIO',
                  icon: const Icon(
                    Icons.download_rounded,
                    color: AppTheme.deepEmerald,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlexCardBubble(ChatMessage msg) {
    final flex = msg.flexPayload ?? const <String, dynamic>{};
    final appTitle = (flex['app_title'] ?? 'BC Mini-App').toString();
    final title = (flex['title'] ?? msg.cleanContent).toString();
    final subtitle = (flex['subtitle'] ?? '').toString();
    final highlight = (flex['highlight'] ?? '').toString();
    final badge = (flex['badge'] ?? 'Super App Card').toString();
    final note = (flex['note'] ?? '').toString();
    final colorHex = (flex['color'] ?? '#06C755').toString();
    final iconName = (flex['icon'] ?? 'widgets').toString();
    final accent = AppTheme.parseHexColor(colorHex);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: accent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  AppTheme.resolveMiniAppIcon(iconName),
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slateDark,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.slateBody,
                    ),
                  ),
                ],
                if (highlight.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'รายละเอียดสำคัญ',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            highlight,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final appCode = (flex['app_code'] ?? '').toString();
                      final targetApp = widget.miniApps.isNotEmpty
                          ? widget.miniApps.firstWhere(
                              (a) => a.code == appCode,
                              orElse: () => widget.miniApps.first,
                            )
                          : MiniAppItem(
                              id: 'custom',
                              code: appCode.isEmpty ? 'leave' : appCode,
                              title: appTitle,
                              subtitle: subtitle,
                              category: 'บริการเสริม',
                              icon: iconName,
                              color: colorHex,
                              url: '/miniapp/$appCode',
                              enabled: true,
                            );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MiniAppRunnerScreen(
                            miniApp: targetApp,
                            conversations: widget.allConversations,
                            initialConversationId: _conversation.id,
                            onCardSent: (_) {
                              _refreshMessagesQuietly();
                              widget.onConversationUpdated?.call();
                            },
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: accent,
                    ),
                    label: Text(
                      'เปิดดูในระบบเสริม ($appTitle)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerPickerPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ส่งสติ๊กเกอร์ BC Official (คลิกเพื่อส่งทันที)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _showStickerPicker = false),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _thaiStickers.map((stk) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _sendSticker(stk),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        stk['emoji']!,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        stk['label']!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateDark,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBanner(ChatMessage replyMsg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFF8FAFC),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.reply_rounded,
            size: 18,
            color: AppTheme.deepEmerald,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ตอบกลับ ${replyMsg.senderName}: ${replyMsg.previewText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateDark,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _replyingTo = null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _isConfidentialMode ? const Color(0xFFFFFBEB) : Colors.white,
        border: Border(
          top: BorderSide(
            color: _isConfidentialMode
                ? AppTheme.dangerRed
                : AppTheme.borderSubtle,
            width: _isConfidentialMode ? 1.5 : 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // DeepSeek AI Assistant Quick Bar above composer
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _insertAiMention,
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6D28D9), Color(0xFF2563EB)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.psychology_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            SizedBox(width: 5),
                            Text(
                              '@ai ถามสมองกลในกลุ่ม',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _openAiAssistModal(initialMode: 'polite'),
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.personalPurple.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_fix_high_rounded,
                              size: 14,
                              color: AppTheme.personalPurple,
                            ),
                            SizedBox(width: 5),
                            Text(
                              '🪄 AI เกลาคำพูด / แนะนำคำตอบ',
                              style: TextStyle(
                                color: AppTheme.personalPurple,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () =>
                          _openAiAssistModal(initialMode: 'smart_reply'),
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.softEmerald,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.tips_and_updates_rounded,
                              size: 14,
                              color: AppTheme.deepEmerald,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'คิดคำตอบด่วนจากแชทล่าสุด',
                              style: TextStyle(
                                color: AppTheme.deepEmerald,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _openAiSummarizeModal,
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0E7FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.summarize_rounded,
                              size: 14,
                              color: AppTheme.workBlue,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'สรุปงาน & Action Items',
                              style: TextStyle(
                                color: AppTheme.workBlue,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isConfidentialMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 15,
                      color: AppTheme.dangerRed,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '🔒 โหมดความลับองค์กร (Confidential): ซ่อนเนื้อหาอัตโนมัติ · ฝังลายน้ำชื่อผู้เปิดอ่าน · ส่งผิดสั่งลบทำลายไฟล์ได้ทันที',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.dangerRed,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _isConfidentialMode = false),
                      child: const Text(
                        'ปิดโหมดความลับ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateBody,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _isUploading ? null : _showAttachmentMenu,
                  tooltip: 'แนบรูปภาพ / ไฟล์เอกสารเก็บถาวรบน MinIO',
                  icon: _isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.attach_file_rounded,
                          color: AppTheme.slateBody,
                        ),
                ),
                IconButton(
                  onPressed: _openMiniAppPicker,
                  tooltip: 'ส่งการ์ดจากระบบเสริม Super App (LINE Flex Card)',
                  icon: const Icon(
                    Icons.widgets_outlined,
                    color: AppTheme.deepEmerald,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _showStickerPicker = !_showStickerPicker),
                  tooltip: 'ส่งสติ๊กเกอร์',
                  icon: Icon(
                    Icons.emoji_emotions_outlined,
                    color: _showStickerPicker
                        ? AppTheme.lineEmerald
                        : AppTheme.slateBody,
                  ),
                ),
                const SizedBox(width: 4),
                // Confidential Mode Toggle Switch Button
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(
                    () => _isConfidentialMode = !_isConfidentialMode,
                  ),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _isConfidentialMode
                          ? const Color(0xFF991B1B)
                          : AppTheme.surfaceBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _isConfidentialMode
                            ? const Color(0xFF991B1B)
                            : AppTheme.borderSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          _isConfidentialMode
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 14,
                          color: _isConfidentialMode
                              ? const Color(0xFFFDE68A)
                              : AppTheme.slateBody,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'โหมดความลับ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _isConfidentialMode
                                ? Colors.white
                                : AppTheme.slateBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    onSubmitted: (_) => _sendTextMessage(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: _isConfidentialMode
                          ? '🔒 พิมพ์ข้อความลับเฉพาะองค์กร (ส่งผิดลบได้ทันที)...'
                          : 'พิมพ์ข้อความถึง ${_conversation.name} (ส่งผิดลบได้)...',
                      fillColor: _isConfidentialMode
                          ? Colors.white
                          : AppTheme.surfaceBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  width: 44,
                  child: ElevatedButton(
                    onPressed: _sendTextMessage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConfidentialMode
                          ? const Color(0xFF991B1B)
                          : AppTheme.lineEmerald,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog showing Permanent MinIO Vault (Images, Files) & Group Notes
class _RoomVaultDialog extends StatefulWidget {
  final Conversation conversation;

  const _RoomVaultDialog({required this.conversation});

  @override
  State<_RoomVaultDialog> createState() => _RoomVaultDialogState();
}

class _RoomVaultDialogState extends State<_RoomVaultDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  VaultData _vault = const VaultData(images: [], files: [], links: []);
  List<NoteItem> _roomNotes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadVault();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVault() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.fetchVault(widget.conversation.id),
        ApiService.instance.fetchNotes(conversationId: widget.conversation.id),
      ]);
      if (!mounted) return;
      setState(() {
        _vault = results[0] as VaultData;
        _roomNotes = results[1] as List<NoteItem>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addRoomNoteDialog() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('สร้างโน้ตประจำห้องแชท'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'หัวข้อโน้ต'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: contentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'รายละเอียด / ข้อตกลงของห้อง',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await ApiService.instance.createNote(
                conversationId: widget.conversation.id,
                title: titleCtrl.text.trim(),
                content: contentCtrl.text.trim(),
                category: 'โน้ตประจำห้อง',
              );
              _loadVault();
            },
            child: const Text('บันทึกโน้ต'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 14, 12),
              decoration: const BoxDecoration(
                color: AppTheme.slateDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_done_rounded,
                        color: AppTheme.lineEmerald,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'คลังรูปภาพ ไฟล์ถาวร & โน้ต — ${widget.conversation.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const PillBadge(
                    text:
                        'เก็บถาวรบน MinIO (bcapp-storage) · ส่งผิดกดลบทำลายไฟล์ได้ทันที',
                    backgroundColor: Color(0xFF064E3B),
                    textColor: Color(0xFF6EE7B7),
                    icon: Icons.verified_rounded,
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    controller: _tabCtrl,
                    indicatorColor: AppTheme.lineEmerald,
                    labelColor: Colors.white,
                    unselectedLabelColor: const Color(0xFF94A3B8),
                    tabs: [
                      Tab(text: 'รูปภาพ (${_vault.images.length})'),
                      Tab(text: 'ไฟล์เอกสาร (${_vault.files.length})'),
                      Tab(text: 'โน้ตประจำห้อง (${_roomNotes.length})'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildImagesGrid(),
                        _buildFilesList(),
                        _buildRoomNotesList(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesGrid() {
    if (_vault.images.isEmpty) {
      return const Center(
        child: Text(
          'ยังไม่มีรูปภาพในคลังของห้องแชทนี้',
          style: TextStyle(color: AppTheme.slateMuted),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _vault.images.length,
      itemBuilder: (ctx, i) {
        final msg = _vault.images[i];
        final url = msg.attachment?.url ?? '';
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url.isNotEmpty)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.image),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  color: Colors.black54,
                  child: Text(
                    msg.attachment?.fileName ?? msg.cleanContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilesList() {
    if (_vault.files.isEmpty) {
      return const Center(
        child: Text(
          'ยังไม่มีไฟล์เอกสารในคลังถาวรของห้องนี้',
          style: TextStyle(color: AppTheme.slateMuted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _vault.files.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final msg = _vault.files[i];
        final att = msg.attachment;
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.borderSubtle),
          ),
          leading: const Icon(
            Icons.description_rounded,
            color: AppTheme.workBlue,
          ),
          title: Text(
            att?.fileName ?? msg.cleanContent,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: Text(
            'ส่งโดย ${msg.senderName} (${msg.senderDepartment}) · ${formatFileSize(att?.fileSize ?? 0)}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () {
                  final url = att?.url ?? '';
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                tooltip: 'ดาวน์โหลดไฟล์',
                icon: const Icon(
                  Icons.download_rounded,
                  color: AppTheme.deepEmerald,
                ),
              ),
              IconButton(
                onPressed: () async {
                  await ApiService.instance.unsendMessage(msg.id, hard: true);
                  await _loadVault();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.dangerRed,
                      content: Text(
                        'ลบข้อความและทำลายไฟล์ออกจากเซิร์ฟเวอร์เรียบร้อยแล้ว',
                      ),
                    ),
                  );
                },
                tooltip: 'สั่งลบและทำลายไฟล์ออกจาก MinIO',
                icon: const Icon(
                  Icons.delete_forever_rounded,
                  color: AppTheme.dangerRed,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoomNotesList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'สมุดโน้ตและข้อตกลงประจำห้องแชท',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addRoomNoteDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('เพิ่มโน้ตห้อง'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _roomNotes.isEmpty
              ? const Center(
                  child: Text(
                    'ยังไม่มีโน้ตประจำห้องแชทนี้',
                    style: TextStyle(color: AppTheme.slateMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _roomNotes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final note = _roomNotes[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            note.content,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// DeepSeek AI Room Summary & Action Items Modal
class _AiSummaryModal extends StatefulWidget {
  final Conversation conversation;
  final Future<void> Function(String formattedText) onSendToRoom;
  final Future<void> Function(String formattedText) onSaveToKeep;

  const _AiSummaryModal({
    required this.conversation,
    required this.onSendToRoom,
    required this.onSaveToKeep,
  });

  @override
  State<_AiSummaryModal> createState() => _AiSummaryModalState();
}

class _AiSummaryModalState extends State<_AiSummaryModal> {
  AiSummaryResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runSummarize();
  }

  Future<void> _runSummarize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.instance.summarizeConversation(
        widget.conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4C1D95), Color(0xFF1E3A8A)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFFDE68A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '✨ สมองกล DeepSeek AI สรุปแชท & แกะงาน',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'ห้อง: ${widget.conversation.name} · โมเดล: ${res?.model ?? "deepseek-chat"}',
                          style: const TextStyle(
                            color: Color(0xFFDDD6FE),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(42),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: AppTheme.personalPurple,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'สมองกล DeepSeek AI กำลังอ่านบริบทห้องแชทและแกะรายการงาน...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slateBody,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.dangerRed,
                            size: 36,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.dangerRed),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _runSummarize,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('ลองใหม่อีกครั้ง'),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Executive Summary Section
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFDDD6FE),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.push_pin_rounded,
                                      size: 17,
                                      color: AppTheme.personalPurple,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      '📌 สรุปประเด็นสำคัญในห้องแชท (Executive Summary)',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.personalPurple,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  res?.summary ?? '-',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: AppTheme.slateDark,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (res != null && res.actionItems.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.softEmerald,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppTheme.lineEmerald.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.task_alt_rounded,
                                        size: 17,
                                        color: AppTheme.deepEmerald,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        '✅ รายการงานที่ต้องทำต่อ (Action Items)',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.deepEmerald,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...res.actionItems.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '• ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.deepEmerald,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.slateDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          if (res != null && res.decisions.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.lightbulb_rounded,
                                        size: 17,
                                        color: AppTheme.workBlue,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        '💡 ข้อตกลงและการตัดสินใจ (Decisions)',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.workBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...res.decisions.map(
                                    (d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $d',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.slateDark,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            if (!_loading && res != null)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final text = res.toFormattedNote();
                        Navigator.pop(context);
                        await widget.onSaveToKeep(text);
                      },
                      icon: const Icon(
                        Icons.bookmark_add_rounded,
                        size: 17,
                        color: AppTheme.deepEmerald,
                      ),
                      label: const Text('บันทึกเข้า BC Keep'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final text = res.toFormattedNote();
                        Navigator.pop(context);
                        await widget.onSendToRoom(text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.personalPurple,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('ส่งสรุปนี้เข้าห้องแชท'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// DeepSeek AI Writing Assistant & Smart Reply Modal
class _AiWritingAssistModal extends StatefulWidget {
  final Conversation conversation;
  final String initialDraft;
  final String initialMode;
  final ValueChanged<String> onApplyToComposer;
  final Future<void> Function(String text) onSendImmediately;

  const _AiWritingAssistModal({
    required this.conversation,
    required this.initialDraft,
    required this.initialMode,
    required this.onApplyToComposer,
    required this.onSendImmediately,
  });

  @override
  State<_AiWritingAssistModal> createState() => _AiWritingAssistModalState();
}

class _AiWritingAssistModalState extends State<_AiWritingAssistModal> {
  late TextEditingController _draftCtrl;
  late String _mode;
  AiAssistResult? _result;
  bool _loading = false;

  static const List<(String, String, IconData)> _modes = [
    ('polite', 'เกลาให้สุภาพเป็นทางการ', Icons.auto_fix_high_rounded),
    ('smart_reply', 'แนะนำคำตอบจากแชทล่าสุด', Icons.tips_and_updates_rounded),
    ('action_plan', 'แปลงเป็นแผนงาน (Action Plan)', Icons.checklist_rounded),
    ('translate_en', 'แปลเป็นภาษาอังกฤษธุรกิจ', Icons.translate_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _draftCtrl = TextEditingController(text: widget.initialDraft);
    _mode = widget.initialMode;
    _runAssist();
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAssist() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.requestAiAssist(
        conversationId: widget.conversation.id,
        mode: _mode,
        text: _draftCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เรียก AI ไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(22),
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
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: AppTheme.personalPurple,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🪄 ผู้ช่วยอัจฉริยะ DeepSeek AI เกลาคำพูด & คิดคำตอบ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        Text(
                          'ช่วยร่างข้อความธุรกิจ ตอบลูกค้า สรุปแผนงาน หรือแปลภาษาในคลิกเดียว',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Mode Selector Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _modes.map((m) {
                  final active = _mode == m.$1;
                  return ChoiceChip(
                    selected: active,
                    selectedColor: const Color(0xFFEDE9FE),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          m.$3,
                          size: 15,
                          color: active
                              ? AppTheme.personalPurple
                              : AppTheme.slateBody,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          m.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active
                                ? AppTheme.personalPurple
                                : AppTheme.slateBody,
                          ),
                        ),
                      ],
                    ),
                    onSelected: (_) {
                      setState(() => _mode = m.$1);
                      _runAssist();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draftCtrl,
                      onSubmitted: (_) => _runAssist(),
                      decoration: const InputDecoration(
                        labelText:
                            'ข้อความร่างของคุณ (เว้นว่างเพื่อให้ AI อ่านจากบริบทแชทล่าสุด)',
                        prefixIcon: Icon(Icons.edit_note_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _runAssist,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.personalPurple,
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: const Text('ให้ AI ช่วยคิด'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.personalPurple,
                    ),
                  ),
                )
              else if (res != null && res.suggestion.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDDD6FE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✨ ข้อความที่ DeepSeek AI แนะนำ:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.personalPurple,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        res.suggestion,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              widget.onApplyToComposer(res.suggestion);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.input_rounded, size: 16),
                            label: const Text('นำไปใส่ช่องพิมพ์'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final txt = res.suggestion;
                              Navigator.pop(context);
                              await widget.onSendImmediately(txt);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.lineEmerald,
                            ),
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('ส่งเข้าห้องแชททันที'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (res.alternatives.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'ตัวเลือกเพิ่มเติม:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...res.alternatives.take(2).map(
                    (alt) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          widget.onApplyToComposer(alt);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  alt,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              const Icon(
                                Icons.north_west_rounded,
                                size: 15,
                                color: AppTheme.personalPurple,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

