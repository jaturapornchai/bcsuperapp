import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import 'chat_room_screen.dart';
import 'mini_app_runner_screen.dart';
import 'notification_settings_sheet.dart';

class MainShell extends StatefulWidget {
  final AppUser currentUser;
  final VoidCallback onLoggedOut;
  final ValueChanged<AppUser> onUserChanged;

  const MainShell({
    super.key,
    required this.currentUser,
    required this.onLoggedOut,
    required this.onUserChanged,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 1; // Default to Chats tab (or Home)
  String _selectedChatFolder = 'all';

  late AppUser _user;
  List<AppUser> _friends = const [];
  List<Conversation> _conversations = const [];
  List<MiniAppItem> _miniApps = const [];
  List<NoteItem> _keepNotes = const [];
  AdminOverview? _adminOverview;
  List<AppUser> _adminUsers = const [];
  AiAdminSettings _aiSettings = const AiAdminSettings(
    model: 'deepseek-chat',
    maskedKey: 'ตั้งค่าบนเซิร์ฟเวอร์แล้ว',
    hasKey: true,
    systemPrompt:
        'คุณคือสมองกลอัจฉริยะ BC DeepSeek AI ประจำองค์กรและทุกกลุ่มแชท เชี่ยวชาญงานบริหาร ฝ่ายขาย บัญชีการเงิน และการสรุปงานกระชับชัดเจน',
    enabled: true,
  );

  Conversation? _activeConversation;
  bool _isLoadingInitial = true;

  // Global search in Chats tab
  final TextEditingController _chatSearchCtrl = TextEditingController();
  String _chatSearchQuery = '';
  List<ChatMessage> _globalSearchResults = const [];
  bool _isSearchingGlobal = false;

  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
    _loadAllData().then(
      (_) => PushService.instance.listenForOpens(_openConversationById),
    );
    _wsSub = ApiService.instance.wsEvents.listen((event) {
      _refreshConversationsAndFriends();
      final convId = event['conversation_id']?.toString();
      NotificationService.instance.handleWsEvent(
        event,
        myUserId: _user.id,
        room: _conversations.where((c) => c.id == convId).firstOrNull,
      );
    });
    NotificationService.instance.onOpenConversation = _openConversationById;
    NotificationService.instance.init();
    PushService.instance.start();
  }

  /// Tap on a message pop-up: bring that room on screen.
  void _openConversationById(String conversationId) {
    if (!mounted) return;
    final conv = _conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conv == null) return;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    if (!isWide) Navigator.of(context).popUntil((route) => route.isFirst);
    _selectConversation(conv, isWide: isWide);
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.id != widget.currentUser.id) {
      _user = widget.currentUser;
      _activeConversation = null;
      _loadAllData();
      PushService.instance.start();
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    if (NotificationService.instance.onOpenConversation ==
        _openConversationById) {
      NotificationService.instance.onOpenConversation = null;
    }
    _chatSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoadingInitial = true);
    try {
      final results = await Future.wait([
        ApiService.instance.fetchFriends(),
        ApiService.instance.fetchConversations(folder: 'all'),
        ApiService.instance.fetchMiniApps(),
        ApiService.instance.fetchNotes(),
      ]);

      final friends = results[0] as List<AppUser>;
      final convs = results[1] as List<Conversation>;
      final apps = results[2] as List<MiniAppItem>;
      final notes = results[3] as List<NoteItem>;

      if (!mounted) return;
      setState(() {
        _friends = friends;
        _conversations = convs;
        _miniApps = apps;
        _keepNotes = notes;
        if (_activeConversation != null) {
          final updatedActive = convs
              .where((c) => c.id == _activeConversation!.id)
              .toList();
          if (updatedActive.isNotEmpty) {
            _activeConversation = updatedActive.first;
          }
        } else if (convs.isNotEmpty) {
          _activeConversation = convs.first;
        }
        _isLoadingInitial = false;
      });

      _loadAdminDataQuietly();
    } catch (_) {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _refreshConversationsAndFriends() async {
    try {
      final results = await Future.wait([
        ApiService.instance.fetchConversations(folder: 'all'),
        ApiService.instance.fetchFriends(),
        ApiService.instance.fetchMiniApps(),
      ]);
      if (!mounted) return;
      final convs = results[0] as List<Conversation>;
      setState(() {
        _conversations = convs;
        _friends = results[1] as List<AppUser>;
        _miniApps = results[2] as List<MiniAppItem>;
        if (_activeConversation != null) {
          final match = convs
              .where((c) => c.id == _activeConversation!.id)
              .toList();
          if (match.isNotEmpty) {
            _activeConversation = match.first;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _loadAdminDataQuietly() async {
    try {
      final results = await Future.wait([
        ApiService.instance.fetchAdminOverview(),
        ApiService.instance.fetchAdminUsers(),
        ApiService.instance.fetchAdminMiniApps(),
        ApiService.instance.fetchAdminAiSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _adminOverview = results[0] as AdminOverview?;
        _adminUsers = results[1] as List<AppUser>;
        final adminApps = results[2] as List<MiniAppItem>;
        if (adminApps.isNotEmpty) {
          _miniApps = adminApps;
        }
        _aiSettings = results[3] as AiAdminSettings;
      });
    } catch (_) {}
  }

  Future<void> _performGlobalSearch(String query) async {
    setState(() => _chatSearchQuery = query);
    if (query.trim().length < 2) {
      setState(() {
        _globalSearchResults = const [];
        _isSearchingGlobal = false;
      });
      return;
    }
    setState(() => _isSearchingGlobal = true);
    try {
      final found = await ApiService.instance.searchMessages(query);
      if (!mounted) return;
      setState(() {
        _globalSearchResults = found;
        _isSearchingGlobal = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isSearchingGlobal = false);
    }
  }

  int get _totalUnreadCount {
    return _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
  }

  List<Conversation> get _filteredConversations {
    final q = _chatSearchQuery.trim().toLowerCase();
    return _conversations.where((c) {
      if (_selectedChatFolder == 'personal' && c.folder != 'personal') {
        return false;
      }
      if (_selectedChatFolder == 'work' && c.folder != 'work') {
        return false;
      }
      if (_selectedChatFolder == 'group' && !c.isGroup) {
        return false;
      }
      if (_selectedChatFolder == 'pinned' && !c.isPinned) {
        return false;
      }
      if (_selectedChatFolder == 'unread' && c.unreadCount <= 0) {
        return false;
      }
      if (q.isNotEmpty) {
        final matchName = c.name.toLowerCase().contains(q);
        final matchLast =
            c.lastMessage?.previewText.toLowerCase().contains(q) ?? false;
        return matchName || matchLast;
      }
      return true;
    }).toList();
  }

  void _selectConversation(Conversation conv, {required bool isWide}) {
    setState(() {
      _activeConversation = conv;
      if (isWide && _selectedIndex != 0 && _selectedIndex != 1) {
        _selectedIndex = 1;
      }
    });
    if (!isWide) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversation: conv,
            allConversations: _conversations,
            miniApps: _miniApps.where((m) => m.enabled).toList(),
            isEmbedded: false,
            onConversationUpdated: _refreshConversationsAndFriends,
          ),
        ),
      );
    }
  }

  Future<void> _openChatWithFriend(
    AppUser friend, {
    required bool isWide,
  }) async {
    try {
      final conv = await ApiService.instance.openDirectConversation(friend.id);
      await _refreshConversationsAndFriends();
      if (!mounted) return;
      _selectConversation(conv, isWide: isWide);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถเปิดห้องสนทนาได้: $e')));
    }
  }

  void _openMiniApp(MiniAppItem app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniAppRunnerScreen(
          miniApp: app,
          conversations: _conversations,
          initialConversationId: _activeConversation?.id,
          onCardSent: (_) => _refreshConversationsAndFriends(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Modals: My QR Code, Edit Profile, Add Friend, Create Group
  // ---------------------------------------------------------------------------
  Future<void> _showMyQrDialog() async {
    final qrData = _user.qrToken.isNotEmpty
        ? _user.qrToken
        : 'bcapp://add/${_user.bcId.isNotEmpty ? _user.bcId : _user.email}';

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'QR Code เพิ่มเพื่อนของฉัน',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                UserAvatar(
                  name: _user.displayName,
                  avatarUrl: _user.avatarUrl,
                  radius: 28,
                  showOnline: true,
                ),
                const SizedBox(height: 8),
                Text(
                  _user.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'BC ID: @${_user.bcId} · ${_user.email}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.slateMuted,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppTheme.slateDark,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'QR Token: $qrData',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: qrData));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('คัดลอก QR Token เรียบร้อยแล้ว'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        tooltip: 'คัดลอก QR Token',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditProfileDialog() async {
    final nameCtrl = TextEditingController(text: _user.displayName);
    final bcIdCtrl = TextEditingController(text: _user.bcId);
    final statusCtrl = TextEditingController(text: _user.statusMessage);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('แก้ไขโปรไฟล์ & ตั้งค่า BC ID'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'ชื่อที่แสดง (Display Name)',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bcIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'BC ID (ให้เพื่อนใช้ค้นหาคุณ)',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: statusCtrl,
                decoration: const InputDecoration(
                  labelText: 'คำคม / สถานะการทำงาน (Status Message)',
                  prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
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
              try {
                final updated = await ApiService.instance.updateProfile(
                  displayName: nameCtrl.text,
                  bcId: bcIdCtrl.text,
                  statusMessage: statusCtrl.text,
                );
                if (!mounted) return;
                setState(() => _user = updated);
                widget.onUserChanged(updated);
                if (ctx.mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.brandDeep,
                    content: Text('บันทึกโปรไฟล์และ BC ID เรียบร้อยแล้ว'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('อัปเดตไม่สำเร็จ: $e')));
              }
            },
            child: const Text('บันทึกการเปลี่ยนแปลง'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFriendDialog({required bool isWide}) async {
    final searchCtrl = TextEditingController();
    List<AppUser> results = const [];
    bool searching = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> runSearch() async {
              final q = searchCtrl.text.trim();
              if (q.isEmpty) return;
              setModalState(() => searching = true);
              final found = await ApiService.instance.searchUsers(q);
              setModalState(() {
                results = found;
                searching = false;
              });
            }

            Future<void> addDirectByInput() async {
              final q = searchCtrl.text.trim();
              if (q.isEmpty) return;
              try {
                await ApiService.instance.addFriend(
                  bcId: q.contains('@') ? null : q,
                  email: q.contains('@') ? q : null,
                  qrToken: q,
                );
                await _refreshConversationsAndFriends();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.brandDeep,
                    content: Text('เพิ่มเพื่อนและสร้างห้องแชทเรียบร้อยแล้ว!'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('ไม่พบผู้ใช้: $q')));
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
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
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppTheme.brandSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.person_add_alt_1_rounded,
                              color: AppTheme.brandDeep,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'เพิ่มเพื่อนใหม่ (BC ID / Gmail / QR Token)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'ค้นหาด้วย BC ID, อีเมล Gmail หรือวาง QR Token ของเพื่อน',
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: searchCtrl,
                              onSubmitted: (_) => runSearch(),
                              decoration: const InputDecoration(
                                hintText:
                                    'พิมพ์เช่น somchai, nida.acc@bcapp.local หรือ QR Token',
                                prefixIcon: Icon(Icons.search_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: runSearch,
                            child: const Text('ค้นหา'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (searching)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (results.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: results.length,
                            separatorBuilder: (context, index) =>
                                const Divider(),
                            itemBuilder: (context, idx) {
                              final u = results[idx];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: UserAvatar(
                                  name: u.displayName,
                                  avatarUrl: u.avatarUrl,
                                  radius: 19,
                                ),
                                title: Text(
                                  u.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: Text(
                                  'BC ID: @${u.bcId} · ${u.email}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () async {
                                    await ApiService.instance.addFriend(
                                      targetId: u.id,
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    await _openChatWithFriend(
                                      u,
                                      isWide: isWide,
                                    );
                                  },
                                  child: const Text('เพิ่มเพื่อน & แชท'),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('ปิด'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: addDirectByInput,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('เพิ่มเพื่อนตามค่าที่กรอกทันที'),
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
      },
    );
  }

  Future<void> _showCreateGroupDialog({required bool isWide}) async {
    final nameCtrl = TextEditingController();
    String folder = 'work';
    final selectedMemberIds = <String>{};

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('สร้างกลุ่มแชทใหม่ (แยกหมวดงาน/ส่วนตัว)'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อกลุ่มแชท',
                        hintText: 'เช่น ทีมบริหารโครงการ BC Cloud',
                        prefixIcon: Icon(Icons.groups_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'หมวดหมู่โฟลเดอร์ของกลุ่ม',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('เรื่องงาน (Work)'),
                          selected: folder == 'work',
                          onSelected: (_) =>
                              setModalState(() => folder = 'work'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('ส่วนตัว (Personal)'),
                          selected: folder == 'personal',
                          onSelected: (_) =>
                              setModalState(() => folder = 'personal'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'เลือกสมาชิกเข้ากลุ่ม',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView(
                        shrinkWrap: true,
                        children: _friends.map((f) {
                          final checked = selectedMemberIds.contains(f.id);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: checked,
                            title: Text(
                              f.displayName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              f.email,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true) {
                                  selectedMemberIds.add(f.id);
                                } else {
                                  selectedMemberIds.remove(f.id);
                                }
                              });
                            },
                          );
                        }).toList(),
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
                ElevatedButton.icon(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final conv = await ApiService.instance
                        .createGroupConversation(
                          name: nameCtrl.text.trim(),
                          folder: folder,
                          memberIds: selectedMemberIds.toList(),
                        );
                    await _refreshConversationsAndFriends();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    _selectConversation(conv, isWide: isWide);
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('สร้างกลุ่มแชท'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build Responsive Shell
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _buildDesktopNavRail(),
            if (_selectedIndex == 0 || _selectedIndex == 1) ...[
              SizedBox(
                width: 390,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: AppTheme.borderSubtle),
                    ),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppTheme.motionMed,
                    transitionBuilder: AppTheme.fadeSlideTransition,
                    child: KeyedSubtree(
                      key: ValueKey('list-$_selectedIndex'),
                      child: _selectedIndex == 0
                          ? _buildHomeTab(isWide: true)
                          : _buildChatsTab(isWide: true),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppTheme.motionMed,
                  transitionBuilder: AppTheme.fadeSlideTransition,
                  child: _activeConversation != null
                      ? ChatRoomScreen(
                          key: ValueKey('room-${_activeConversation!.id}'),
                          conversation: _activeConversation!,
                          allConversations: _conversations,
                          miniApps: _miniApps.where((m) => m.enabled).toList(),
                          isEmbedded: true,
                          onConversationUpdated:
                              _refreshConversationsAndFriends,
                          onThemeChanged: (_) => setState(() {}),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('room-empty'),
                          child: _buildEmptyChatPlaceholder(),
                        ),
                ),
              ),
            ] else
              Expanded(child: _buildSelectedTabBody(isWide: true)),
          ],
        ),
      );
    }

    // Mobile / Narrow Layout
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppTheme.motionMed,
          transitionBuilder: AppTheme.fadeSlideTransition,
          child: KeyedSubtree(
            key: ValueKey('tab-$_selectedIndex'),
            child: _buildSelectedTabBody(isWide: false),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
          boxShadow: [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (idx) {
            setState(() => _selectedIndex = idx);
            if (idx == 4) _loadAdminDataQuietly();
          },
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.brandSoft,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppTheme.brandDeep),
              label: 'หน้าหลัก',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _totalUnreadCount > 0,
                backgroundColor: AppTheme.brandPrimary,
                label: Text('$_totalUnreadCount'),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: _totalUnreadCount > 0,
                backgroundColor: AppTheme.brandPrimary,
                label: Text('$_totalUnreadCount'),
                child: Icon(
                  Icons.chat_bubble_rounded,
                  color: AppTheme.brandDeep,
                ),
              ),
              label: 'แชท',
            ),
            NavigationDestination(
              icon: Icon(Icons.widgets_outlined),
              selectedIcon: Icon(
                Icons.widgets_rounded,
                color: AppTheme.brandDeep,
              ),
              label: 'บริการเสริม',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border_rounded),
              selectedIcon: Icon(
                Icons.bookmark_rounded,
                color: AppTheme.brandDeep,
              ),
              label: 'BC Keep',
            ),
            if (_user.isAdmin)
              NavigationDestination(
                icon: Icon(Icons.admin_panel_settings_outlined),
                selectedIcon: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: AppTheme.brandDeep,
                ),
                label: 'หลังบ้าน',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTabBody({required bool isWide}) {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeTab(isWide: isWide);
      case 1:
        return _buildChatsTab(isWide: isWide);
      case 2:
        return _buildMiniAppsCenterTab();
      case 3:
        return _buildKeepVaultTab();
      case 4 when _user.isAdmin:
        return _buildAdminBackofficeTab();
      default:
        return _buildChatsTab(isWide: isWide);
    }
  }

  Widget _buildDesktopNavRail() {
    final navItems = [
      (0, Icons.home_rounded, 'หน้าหลัก', 0),
      (1, Icons.chat_bubble_rounded, 'แชท', _totalUnreadCount),
      (2, Icons.widgets_rounded, 'บริการเสริม', 0),
      (3, Icons.bookmark_rounded, 'BC Keep', 0),
      if (_user.isAdmin) (4, Icons.admin_panel_settings_rounded, 'หลังบ้าน', 0),
    ];
    const idleColor = Color(0xFF94A3B8);

    return Container(
      width: 84,
      decoration: const BoxDecoration(gradient: AppTheme.navyGradient),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: _showEditProfileDialog,
            borderRadius: BorderRadius.circular(999),
            child: UserAvatar(
              name: _user.displayName,
              avatarUrl: _user.avatarUrl,
              radius: 21,
              showOnline: true,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.brandPrimary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Super App',
              maxLines: 1,
              style: TextStyle(
                color: Color(0xFF4ADE80),
                fontSize: 9.5,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              children: navItems.map((item) {
                final idx = item.$1;
                final icon = item.$2;
                final label = item.$3;
                final badgeCount = item.$4;
                final selected = _selectedIndex == idx;
                final fg = selected ? Colors.white : idleColor;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      hoverColor: Colors.white.withValues(alpha: 0.08),
                      onTap: () {
                        setState(() => _selectedIndex = idx);
                        if (idx == 4) _loadAdminDataQuietly();
                      },
                      child: AnimatedContainer(
                        duration: AppTheme.motionMed,
                        curve: AppTheme.motionCurve,
                        width: 68,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: selected ? AppTheme.brandGradient : null,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          boxShadow: selected
                              ? AppTheme.glow(AppTheme.brandPrimary)
                              : const [],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Badge(
                              isLabelVisible: badgeCount > 0,
                              backgroundColor: AppTheme.dangerRed,
                              label: Text('$badgeCount'),
                              child: Icon(icon, color: fg, size: 22),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: fg,
                                fontSize: 10.5,
                                height: 1.35,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          IconButton(
            onPressed: _showMyQrDialog,
            tooltip: 'QR Code ของฉัน',
            icon: const Icon(Icons.qr_code_2_rounded, color: Color(0xFFCBD5E1)),
          ),
          IconButton(
            onPressed: widget.onLoggedOut,
            tooltip: 'สลับบัญชี Gmail / ออกจากระบบ',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChatPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surfaceBg, AppTheme.brandSoft],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          boxShadow: AppTheme.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
                boxShadow: AppTheme.glow(AppTheme.brandPrimary),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'เลือกห้องแชทหรือเพื่อนด้านซ้ายเพื่อเริ่มสนทนา',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ซิงค์แชทข้ามเครื่องด้วย Gmail · ไฟล์และรูปภาพเก็บถาวรบน MinIO ไม่หมดอายุ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 0: หน้าหลัก (HOME — โปรไฟล์, QR, เพิ่มเพื่อน, บริการเสริม, กลุ่ม & เพื่อน)
  // ---------------------------------------------------------------------------
  /// หัวข้อส่วน (titleMedium w700 + คำอธิบายจาง ๆ) ใช้ร่วมทุกแท็บ
  Widget _sectionHeader(
    String title, {
    String? subtitle,
    Widget? trailing,
    EdgeInsetsGeometry padding = const EdgeInsets.only(bottom: 12),
  }) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.slateMuted,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// ปุ่มลัด: ไอคอนในกรอบมนสีอ่อน + ป้ายชื่อ อยู่กึ่งกลาง
  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.borderSubtle),
            boxShadow: AppTheme.shadowSm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab({required bool isWide}) {
    final groups = _conversations.where((c) => c.isGroup).toList();
    final officials = _conversations.where((c) => c.isOfficial).toList();
    final enabledMiniApps = _miniApps.where((m) => m.enabled).toList();

    return Column(
      children: [
        // Top Header
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'หน้าหลัก',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PillBadge(
                    text: 'Gmail Cloud Sync',
                    backgroundColor: AppTheme.brandSoft,
                    textColor: AppTheme.brandDeep,
                    icon: Icons.cloud_done_rounded,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _showAddFriendDialog(isWide: isWide),
                tooltip: 'เพิ่มเพื่อนด้วย BC ID / Gmail / QR',
                icon: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: AppTheme.slateDark,
                ),
              ),
              IconButton(
                onPressed: () => _showCreateGroupDialog(isWide: isWide),
                tooltip: 'สร้างกลุ่มแชทใหม่',
                icon: const Icon(
                  Icons.group_add_rounded,
                  color: AppTheme.slateDark,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // My Profile Card (hero)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.navyGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        UserAvatar(
                          name: _user.displayName,
                          avatarUrl: _user.avatarUrl,
                          radius: 24,
                          showOnline: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _user.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        height: 1.35,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  PillBadge(
                                    text: _user.department,
                                    backgroundColor: AppTheme.brandPrimary
                                        .withValues(alpha: 0.25),
                                    textColor: const Color(0xFF4ADE80),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'BC ID: @${_user.bcId} · ${_user.email}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontSize: 12,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _user.statusMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: _showMyQrDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.brandPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.qr_code_rounded, size: 16),
                              label: const Text(
                                'QR ของฉัน',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: _showEditProfileDialog,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.edit_rounded, size: 15),
                              label: const Text(
                                'ตั้งค่า BC ID',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quick Action Buttons (Add Friend & Create Group)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _quickActionTile(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'เพิ่มเพื่อน',
                      color: AppTheme.brandDeep,
                      onTap: () => _showAddFriendDialog(isWide: isWide),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _quickActionTile(
                      icon: Icons.group_add_rounded,
                      label: 'สร้างกลุ่ม',
                      color: AppTheme.workBlue,
                      onTap: () => _showCreateGroupDialog(isWide: isWide),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Quick Mini-Apps Strip
              _sectionHeader(
                'บริการเสริมด่วน',
                subtitle: 'เปิดใช้งานระบบเสริมขององค์กรได้ทันที',
                padding: const EdgeInsets.only(bottom: 8),
                trailing: TextButton(
                  onPressed: () => setState(() => _selectedIndex = 2),
                  child: const Text(
                    'ดูทั้งหมด',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 64,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: enabledMiniApps.length,
                itemBuilder: (ctx, i) {
                  final app = enabledMiniApps[i];
                  final color = AppTheme.parseHexColor(app.color);
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    onTap: () => _openMiniApp(app),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: AppTheme.borderSubtle),
                        boxShadow: AppTheme.shadowSm,
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              app.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slateDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Official Accounts Section
              if (officials.isNotEmpty) ...[
                _sectionHeader(
                  'บัญชีทางการ (${officials.length})',
                  subtitle: 'ประกาศสำคัญและข่าวสารขององค์กร',
                  padding: const EdgeInsets.only(bottom: 4),
                ),
                ...officials.map(
                  (c) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    leading: UserAvatar(
                      name: c.name,
                      avatarUrl: c.avatarUrl,
                      radius: 20,
                      isOfficial: true,
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      c.lastMessage?.previewText ?? 'ประกาศสำคัญขององค์กร',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _selectConversation(c, isWide: isWide),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Groups Section
              _sectionHeader(
                'กลุ่มสนทนา (${groups.length})',
                padding: const EdgeInsets.only(bottom: 4),
              ),
              ...groups.map(
                (g) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: UserAvatar(
                    name: g.name,
                    avatarUrl: g.avatarUrl,
                    radius: 20,
                    isGroup: true,
                  ),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '${g.name} (${g.memberCount})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PillBadge(
                        text: g.folderLabel,
                        backgroundColor: g.isWork
                            ? const Color(0xFFDBEAFE)
                            : AppTheme.brandSoft,
                        textColor: g.isWork
                            ? AppTheme.workBlue
                            : AppTheme.brandDeep,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    g.lastMessage?.previewText ?? 'แตะเพื่อเปิดห้องสนทนากลุ่ม',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => _selectConversation(g, isWide: isWide),
                ),
              ),
              const SizedBox(height: 12),

              // Friends Section
              _sectionHeader(
                'เพื่อนร่วมงานและผู้ติดต่อ (${_friends.length})',
                padding: const EdgeInsets.only(bottom: 4),
              ),
              ..._friends.map(
                (f) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: UserAvatar(
                    name: f.displayName,
                    avatarUrl: f.avatarUrl,
                    radius: 20,
                    showOnline: f.isOnline,
                    isOfficial: f.isOfficial,
                  ),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          f.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PillBadge(
                        text: f.department,
                        backgroundColor: const Color(0xFFE0E7FF),
                        textColor: AppTheme.workBlue,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    f.statusMessage.isNotEmpty ? f.statusMessage : f.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: AppTheme.brandDeep,
                    ),
                    onPressed: () => _openChatWithFriend(f, isWide: isWide),
                  ),
                  onTap: () => _openChatWithFriend(f, isWide: isWide),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: แชท (CHATS — แยกหมวดโฟลเดอร์ + ค้นหาข้ามห้อง + รายการแชท)
  // ---------------------------------------------------------------------------
  Widget _buildChatsTab({required bool isWide}) {
    final folders = [
      ('all', 'ทั้งหมด'),
      ('personal', 'ส่วนตัว'),
      ('work', 'เรื่องงาน'),
      ('group', 'กลุ่ม'),
      ('pinned', 'ปักหมุด'),
      ('unread', 'ยังไม่อ่าน'),
    ];
    final items = _filteredConversations;

    return Column(
      children: [
        // Header
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'แชท',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 8),
              if (_totalUnreadCount > 0)
                PillBadge(
                  text: 'ยังไม่อ่าน $_totalUnreadCount',
                  backgroundColor: AppTheme.brandPrimary,
                  textColor: Colors.white,
                ),
              const Spacer(),
              IconButton(
                onPressed: () => showNotificationSettingsSheet(context),
                tooltip: 'เสียงและการแจ้งเตือน',
                icon: const Icon(Icons.notifications_rounded),
              ),
              IconButton(
                onPressed: () => _showCreateGroupDialog(isWide: isWide),
                tooltip: 'สร้างกลุ่มแชทใหม่',
                icon: const Icon(Icons.group_add_rounded),
              ),
              IconButton(
                onPressed: _refreshConversationsAndFriends,
                tooltip: 'รีเฟรชรายการแชท',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),

        // Search input
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _chatSearchCtrl,
            onChanged: _performGlobalSearch,
            decoration: InputDecoration(
              hintText: 'ค้นหาห้องแชท ข้อความ หรือชื่อไฟล์ถาวร...',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _chatSearchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _chatSearchCtrl.clear();
                        _performGlobalSearch('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  : null,
            ),
          ),
        ),

        // Folder Filter Bar (Solves Work vs Personal Chat Clutter!)
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: folders.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final code = folders[i].$1;
              final label = folders[i].$2;
              final active = _selectedChatFolder == code;

              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _selectedChatFolder = code),
                    child: AnimatedContainer(
                      duration: AppTheme.motionFast,
                      curve: AppTheme.motionCurve,
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppTheme.slateDark : AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: active
                              ? AppTheme.slateDark
                              : AppTheme.borderSubtle,
                        ),
                        boxShadow: active ? AppTheme.shadowSm : const [],
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: AppTheme.motionFast,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active ? Colors.white : AppTheme.slateBody,
                        ),
                        child: Text(label, maxLines: 1),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),

        // Global message search hits (if searching)
        if (_chatSearchQuery.trim().length >= 2 &&
            (_isSearchingGlobal || _globalSearchResults.isNotEmpty))
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            color: const Color(0xFFF8FAFC),
            child: _isSearchingGlobal
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _globalSearchResults.length,
                    itemBuilder: (ctx, i) {
                      final m = _globalSearchResults[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.manage_search_rounded,
                          color: AppTheme.brandDeep,
                        ),
                        title: Text(
                          m.previewText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        subtitle: Text(
                          'โดย ${m.senderName} · ${formatThaiTime(m.createdAt)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () {
                          final target = _conversations
                              .where((c) => c.id == m.conversationId)
                              .toList();
                          if (target.isNotEmpty) {
                            _selectConversation(target.first, isWide: isWide);
                          }
                        },
                      );
                    },
                  ),
          ),

        // Conversation List
        Expanded(
          child: _isLoadingInitial
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? const Center(
                  child: Text(
                    'ไม่มีห้องแชทในหมวดหมู่นี้',
                    style: TextStyle(color: AppTheme.slateMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(indent: 76, height: 1),
                  itemBuilder: (ctx, i) {
                    final conv = items[i];
                    final isSelected =
                        isWide && _activeConversation?.id == conv.id;
                    final timeText = formatThaiTime(
                      conv.lastMessage?.createdAt ?? conv.updatedAt,
                    );

                    final hasUnread = conv.unreadCount > 0;
                    return Material(
                      color: isSelected ? AppTheme.brandSoft : Colors.white,
                      child: InkWell(
                        onTap: () => _selectConversation(conv, isWide: isWide),
                        hoverColor: AppTheme.surfaceBg,
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  UserAvatar(
                                    name: conv.name,
                                    avatarUrl: conv.avatarUrl,
                                    radius: 23,
                                    showOnline: !conv.isGroup,
                                    isOfficial: conv.isOfficial,
                                    isGroup: conv.isGroup,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // แถว 1: ปักหมุด · ชื่อ · โฟลเดอร์ · เวลา
                                        SizedBox(
                                          height: 22,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              if (conv.isPinned) ...[
                                                const Icon(
                                                  Icons.push_pin_rounded,
                                                  size: 14,
                                                  color: AppTheme.goldPin,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  conv.isGroup
                                                      ? '${conv.name} (${conv.memberCount})'
                                                      : conv.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    height: 1.35,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.slateDark,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              PillBadge(
                                                text: conv.folderLabel,
                                                backgroundColor: conv.isWork
                                                    ? const Color(0xFFDBEAFE)
                                                    : AppTheme.brandSoft,
                                                textColor: conv.isWork
                                                    ? AppTheme.workBlue
                                                    : AppTheme.brandDeep,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                timeText,
                                                maxLines: 1,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  height: 1.35,
                                                  color: hasUnread
                                                      ? AppTheme.brandDeep
                                                      : AppTheme.slateMuted,
                                                  fontWeight: hasUnread
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        // แถว 2: ข้อความล่าสุด · จำนวนที่ยังไม่อ่าน
                                        SizedBox(
                                          height: 22,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  conv
                                                          .lastMessage
                                                          ?.previewText ??
                                                      'เริ่มการสนทนา...',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    height: 1.35,
                                                    color: hasUnread
                                                        ? AppTheme.slateDark
                                                        : AppTheme.slateMuted,
                                                    fontWeight: hasUnread
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                  ),
                                                ),
                                              ),
                                              if (hasUnread) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  height: 20,
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 20,
                                                      ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                      ),
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        AppTheme.brandPrimary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${conv.unreadCount}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                left: 0,
                                top: 10,
                                bottom: 10,
                                child: Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: AppTheme.brandPrimary,
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: บริการเสริม SUPER APP (DYNAMIC WEBVIEW MINI-APPS CENTER)
  // ---------------------------------------------------------------------------
  Widget _buildMiniAppsCenterTab() {
    final activeApps = _miniApps.where((m) => m.enabled).toList();
    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text(
          'บริการเสริม BC Super App',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_user.isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedIndex = 4),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  icon: const Icon(Icons.settings_suggest_rounded, size: 16),
                  label: Text(
                    isCompact ? 'จัดการ' : 'เพิ่ม/แก้ไขระบบเสริมหลังบ้าน',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 14 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F172A), Color(0xFF064E3B)],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    boxShadow: AppTheme.shadowMd,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          boxShadow: AppTheme.glow(AppTheme.brandPrimary),
                        ),
                        child: const Icon(
                          Icons.widgets_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Super App WebView + JS Bridge (เชื่อมต่อ SSO Gmail อัตโนมัติ)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'เปิดใช้งานระบบเสริมองค์กร ส่งการ์ดข้อความ (Flex Card) เข้าห้องแชทได้ทันที และเพิ่มระบบใหม่จากหลังบ้านโดยไม่ต้องอัปเดตแอป',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: activeApps.map((app) {
                    final color = AppTheme.parseHexColor(app.color);
                    return Container(
                      width: isCompact ? double.infinity : 340,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        border: Border.all(color: AppTheme.borderSubtle),
                        boxShadow: AppTheme.shadowSm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMd,
                                  ),
                                ),
                                child: Icon(
                                  AppTheme.resolveMiniAppIcon(app.icon),
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        height: 1.35,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    PillBadge(
                                      text: app.category,
                                      backgroundColor: color.withValues(
                                        alpha: 0.14,
                                      ),
                                      textColor: color,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            app.subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: AppTheme.slateBody,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _openMiniApp(app),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: color,
                                  ),
                                  icon: const Icon(
                                    Icons.rocket_launch_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('เปิดใช้งาน & ส่งการ์ด'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  final url = ApiService.instance
                                      .resolveMiniAppUrl(app);
                                  final uri = Uri.tryParse(url);
                                  if (uri != null) {
                                    launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                tooltip: 'เปิด WebView URL',
                                icon: const Icon(Icons.open_in_new_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: BC KEEP (คลังบันทึกส่วนตัวถาวร ซิงค์ตาม Gmail)
  // ---------------------------------------------------------------------------
  Widget _buildKeepVaultTab() {
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text(
          'BC Keep — คลังบันทึกถาวร',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _showCreateKeepNoteDialog,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  isCompact ? 'สร้างโน้ต' : 'สร้างบันทึก Keep ใหม่',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 14 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1020),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.brandSoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.35),
                    ),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_rounded, color: AppTheme.brandDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'BC Keep ซิงค์อัตโนมัติตามบัญชี Gmail (${_user.email}) เก็บข้อความ ลิงก์ และไฟล์สำคัญถาวร ไม่มีวันหมดอายุ',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.brandDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_keepNotes.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(36),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      boxShadow: AppTheme.shadowSm,
                    ),
                    child: const Text(
                      'ยังไม่มีรายการใน BC Keep กดปุ่ม "สร้างบันทึก Keep ใหม่" หรือกดบันทึกจากข้อความในห้องแชทได้เลย',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.slateMuted, height: 1.5),
                    ),
                  )
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: _keepNotes.map((note) {
                      return Container(
                        width: isCompact ? double.infinity : 320,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLg,
                          ),
                          border: Border.all(color: AppTheme.borderSubtle),
                          boxShadow: AppTheme.shadowSm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: PillBadge(
                                      text: note.category,
                                      backgroundColor: AppTheme.brandSoft,
                                      textColor: AppTheme.brandDeep,
                                      icon: Icons.bookmark_rounded,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatThaiTime(note.createdAt),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    await ApiService.instance.deleteNote(
                                      note.id,
                                    );
                                    final fresh = await ApiService.instance
                                        .fetchNotes();
                                    if (!mounted) return;
                                    setState(() => _keepNotes = fresh);
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: AppTheme.dangerRed,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              note.title,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              note.content,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: AppTheme.slateBody,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateKeepNoteDialog() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = 'บันทึกสำคัญ';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('สร้างบันทึก BC Keep ใหม่'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'หัวข้อบันทึก',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'ข้อความ / ลิงก์ / รายละเอียดที่ต้องการเก็บถาวร',
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
                title: titleCtrl.text.trim(),
                content: contentCtrl.text.trim(),
                category: category,
              );
              final fresh = await ApiService.instance.fetchNotes();
              if (!mounted) return;
              setState(() => _keepNotes = fresh);
            },
            child: const Text('บันทึกเข้า BC Keep'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: หลังบ้าน (ADMIN BACKOFFICE — จัดการ Mini-App, Broadcast, Users, Stats)
  // ---------------------------------------------------------------------------
  Widget _buildAdminBackofficeTab() {
    final ov = _adminOverview;
    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text(
          'ระบบจัดการหลังบ้าน (Admin Backoffice)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _loadAdminDataQuietly,
            tooltip: 'รีเฟรชข้อมูลหลังบ้าน',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 14 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Overview Metric Cards
                LayoutBuilder(
                  builder: (context, box) {
                    // Phones get an even 2x2 grid; wider screens keep
                    // fixed 255px tiles that fit four per row.
                    final compact = box.maxWidth < 600;
                    final tileWidth = compact ? (box.maxWidth - 12) / 2 : 255.0;
                    return Wrap(
                      spacing: compact ? 12 : 14,
                      runSpacing: compact ? 12 : 14,
                      children: [
                        _buildMetricCard(
                          'ผู้ใช้งานทั้งหมด (Gmail)',
                          '${ov?.totalUsers ?? _adminUsers.length} บัญชี',
                          Icons.people_alt_rounded,
                          AppTheme.brandPrimary,
                          width: tileWidth,
                          compact: compact,
                        ),
                        _buildMetricCard(
                          'ห้องสนทนาทั้งหมด',
                          '${ov?.totalConversations ?? _conversations.length} ห้อง',
                          Icons.forum_rounded,
                          AppTheme.workBlue,
                          width: tileWidth,
                          compact: compact,
                        ),
                        _buildMetricCard(
                          'ข้อความทั้งหมดบน MongoDB',
                          '${ov?.totalMessages ?? 0} ข้อความ',
                          Icons.mark_chat_read_rounded,
                          AppTheme.personalPurple,
                          width: tileWidth,
                          compact: compact,
                        ),
                        _buildMetricCard(
                          'ไฟล์ถาวรบน MinIO (bcapp-storage)',
                          '${ov?.totalFiles ?? 0} ไฟล์ (${formatFileSize(ov?.totalStorageBytes ?? 0)})',
                          Icons.cloud_done_rounded,
                          AppTheme.warningAmber,
                          width: tileWidth,
                          compact: compact,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Business theme (applies to everyone in the organisation)
                _buildBusinessThemeCard(),
                const SizedBox(height: 24),

                // Section 0: DeepSeek AI Brain Configuration
                _buildAiBrainSettingsCard(),
                const SizedBox(height: 24),

                // Section 0.5: 1-Click Employee Handover + AI Briefing
                _buildEmployeeHandoverCard(),
                const SizedBox(height: 24),

                // Section 1: Mini-App Manager
                Container(
                  padding: EdgeInsets.all(isCompact ? 16 : 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppTheme.borderSubtle),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.dashboard_customize_rounded,
                                color: AppTheme.brandPrimary,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'จัดการระบบเสริม WebView (Dynamic Mini-App)',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _showMiniAppFormDialog(),
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('เพิ่มบริการเสริมใหม่'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _miniApps.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (ctx, i) {
                          final app = _miniApps[i];
                          final color = AppTheme.parseHexColor(app.color);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                AppTheme.resolveMiniAppIcon(app.icon),
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                            title: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  app.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                PillBadge(
                                  text: app.category,
                                  backgroundColor: AppTheme.surfaceBg,
                                  textColor: AppTheme.slateBody,
                                ),
                                PillBadge(
                                  text: app.enabled
                                      ? 'เปิดใช้งาน'
                                      : 'ปิดชั่วคราว',
                                  backgroundColor: app.enabled
                                      ? AppTheme.brandSoft
                                      : const Color(0xFFFEE2E2),
                                  textColor: app.enabled
                                      ? AppTheme.brandDeep
                                      : AppTheme.dangerRed,
                                ),
                              ],
                            ),
                            subtitle: Text(
                              'รหัส: ${app.code} · ${app.subtitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: app.enabled,
                                  activeThumbColor: AppTheme.brandPrimary,
                                  onChanged: (val) async {
                                    await ApiService.instance
                                        .updateAdminMiniApp(app.id, {
                                          ...app.toJson(),
                                          'enabled': val,
                                        });
                                    await _loadAdminDataQuietly();
                                  },
                                ),
                                IconButton(
                                  onPressed: () =>
                                      _showMiniAppFormDialog(existing: app),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'แก้ไขบริการเสริม',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section 2: Official OA Broadcast
                _buildBroadcastCard(),
                const SizedBox(height: 24),

                // Section 3: User Management
                _buildUserManagementCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    double width = 255,
    bool compact = false,
  }) {
    final iconTile = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Icon(icon, color: color, size: 22),
    );
    final labelText = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12,
        height: 1.4,
        color: AppTheme.slateMuted,
      ),
    );
    final valueText = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 15.5,
        height: 1.35,
        fontWeight: FontWeight.w800,
        color: AppTheme.slateDark,
      ),
    );
    if (compact) {
      return Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.borderSubtle),
          boxShadow: AppTheme.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            iconTile,
            const SizedBox(height: 12),
            // Two label lines reserved so every tile in the grid is equal height.
            SizedBox(height: 34, child: labelText),
            const SizedBox(height: 4),
            valueText,
          ],
        ),
      );
    }
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconTile,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 4), valueText],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMiniAppFormDialog({MiniAppItem? existing}) async {
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'stock_check',
    );
    final titleCtrl = TextEditingController(
      text: existing?.title ?? 'ระบบเช็คสต็อกสินค้าด่วน',
    );
    final subtitleCtrl = TextEditingController(
      text:
          existing?.subtitle ?? 'ตรวจสอบยอดคงเหลือและส่งการ์ดสต็อกเข้าห้องแชท',
    );
    final categoryCtrl = TextEditingController(
      text: existing?.category ?? 'คลังสินค้า/ขาย',
    );
    final urlCtrl = TextEditingController(
      text: existing?.url ?? '/miniapp/stock_check',
    );
    final colorCtrl = TextEditingController(text: existing?.color ?? '#0EA5E9');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null
              ? 'เพิ่มบริการเสริมใหม่ (WebView Mini-App)'
              : 'แก้ไขบริการเสริม ${existing.title}',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'รหัสบริการ (Code)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อบริการเสริม',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subtitleCtrl,
                  decoration: const InputDecoration(labelText: 'คำอธิบายสั้นๆ'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'WebView URL Path หรือ External URL',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: colorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'สีประจำระบบ (Hex เช่น #06C755)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              final payload = {
                'code': codeCtrl.text.trim(),
                'title': titleCtrl.text.trim(),
                'subtitle': subtitleCtrl.text.trim(),
                'category': categoryCtrl.text.trim(),
                'url': urlCtrl.text.trim(),
                'color': colorCtrl.text.trim(),
                'icon': existing?.icon ?? 'inventory',
                'enabled': existing?.enabled ?? true,
              };
              Navigator.pop(ctx);
              if (existing == null) {
                await ApiService.instance.createAdminMiniApp(payload);
              } else {
                await ApiService.instance.updateAdminMiniApp(
                  existing.id,
                  payload,
                );
              }
              await _loadAdminDataQuietly();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.brandDeep,
                  content: Text(
                    'อัปเดตบริการเสริมเรียบร้อย! ผู้ใช้ทุกคนเห็นทันทีโดยไม่ต้องอัปเดตแอป',
                  ),
                ),
              );
            },
            child: const Text('บันทึกบริการเสริม'),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessThemeCard() {
    final current = AppTheme.preset.value;
    final tileWidth = MediaQuery.sizeOf(context).width < 600
        ? double.infinity
        : 236.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ธีมสีของกิจการ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'เลือกสีให้เข้ากับธุรกิจ เปลี่ยนแล้วทุกคนในองค์กรเห็นทันที',
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in ThemePreset.all)
                SizedBox(
                  width: tileWidth,
                  child: _ThemePresetTile(
                    preset: p,
                    selected: p.code == current.code,
                    onTap: () => _changeBusinessTheme(p),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeBusinessTheme(ThemePreset preset) async {
    if (preset.code == AppTheme.preset.value.code) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.updateBusinessTheme(preset.code);
      messenger.showSnackBar(
        SnackBar(content: Text('เปลี่ยนธีมเป็น "${preset.name}" แล้ว')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Widget _buildAiBrainSettingsCard() {
    String selectedModel = _aiSettings.model;
    final apiKeyCtrl = TextEditingController();
    final promptCtrl = TextEditingController(text: _aiSettings.systemPrompt);

    return StatefulBuilder(
      builder: (ctx, setCardState) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: AppTheme.personalPurple.withValues(alpha: 0.3),
            ),
            boxShadow: AppTheme.shadowMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6D28D9), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              '🧠 ตั้งค่าสมองกล DeepSeek AI ประจำองค์กร',
                              style: TextStyle(
                                fontSize: 15.5,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            PillBadge(
                              text:
                                  'API Key: ${_aiSettings.maskedKey.isNotEmpty ? _aiSettings.maskedKey : "พร้อมใช้งาน"}',
                              backgroundColor: AppTheme.brandSoft,
                              textColor: AppTheme.brandDeep,
                              icon: Icons.verified_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'ทำหน้าที่เป็นผู้ช่วยอัจฉริยะให้พนักงานทุกคนและทุกกลุ่มแชท (@ai ถามในกลุ่ม, สรุปแชท & แกะงาน, เกลาคำพูด)',
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
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'เลือกโมเดล DeepSeek:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  ChoiceChip(
                    selected: selectedModel == 'deepseek-chat',
                    label: const Text('deepseek-chat (DeepSeek-V3)'),
                    onSelected: (_) =>
                        setCardState(() => selectedModel = 'deepseek-chat'),
                  ),
                  ChoiceChip(
                    selected: selectedModel == 'deepseek-reasoner',
                    label: const Text('deepseek-reasoner (DeepSeek-R1)'),
                    onSelected: (_) =>
                        setCardState(() => selectedModel = 'deepseek-reasoner'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText:
                      'อัปเดต DeepSeek API Key (ปัจจุบัน: ${_aiSettings.maskedKey})',
                  hintText:
                      'เว้นว่างไว้หากใช้ API Key เดิมที่ตั้งค่าแล้วบนเซิร์ฟเวอร์',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText:
                      'System Prompt ประจำองค์กร (กำหนดบทบาทและความรู้ของ AI)',
                  prefixIcon: Icon(Icons.tune_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final updated = await ApiService.instance
                          .updateAdminAiSettings(
                            model: selectedModel,
                            apiKey: apiKeyCtrl.text,
                            systemPrompt: promptCtrl.text,
                          );
                      if (!mounted) return;
                      setState(() => _aiSettings = updated);
                      apiKeyCtrl.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppTheme.brandDeep,
                          content: Text(
                            'บันทึกการตั้งค่าสมองกล DeepSeek AI ประจำองค์กรเรียบร้อยแล้ว!',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.personalPurple,
                  ),
                  icon: const Icon(Icons.save_rounded, size: 17),
                  label: const Text('บันทึกตั้งค่าสมองกล DeepSeek AI'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmployeeHandoverCard() {
    final availableUsers = _adminUsers.isNotEmpty ? _adminUsers : _friends;
    String? fromUserId = availableUsers.length > 1
        ? availableUsers[1].id
        : (availableUsers.isNotEmpty ? availableUsers.first.id : null);
    String? toUserId = availableUsers.isNotEmpty
        ? availableUsers.first.id
        : null;
    bool isTransferring = false;
    String? handoverResultNote;

    return StatefulBuilder(
      builder: (ctx, setCardState) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.workBlue.withValues(alpha: 0.3)),
            boxShadow: AppTheme.shadowMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: AppTheme.workBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔄 โอนย้ายห้องแชทและประวัติลูกค้าเมื่อพนักงานลาออก (1-Click Handover + AI Briefing)',
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'โอนสิทธิ์ห้องแชทลูกค้าทั้งหมดให้พนักงานคนใหม่ พร้อมให้สมองกล DeepSeek AI สรุปงานค้างส่งเข้าห้องทันที',
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
              if (availableUsers.isNotEmpty) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 310,
                      child: DropdownButtonFormField<String>(
                        initialValue: fromUserId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'พนักงานต้นทาง (ผู้ส่งมอบงาน / ลาออก)',
                          prefixIcon: Icon(
                            Icons.person_remove_outlined,
                            size: 18,
                          ),
                        ),
                        items: availableUsers.map((u) {
                          return DropdownMenuItem<String>(
                            value: u.id,
                            child: Text(
                              '${u.displayName} (${u.department})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setCardState(() => fromUserId = v),
                      ),
                    ),
                    SizedBox(
                      width: 310,
                      child: DropdownButtonFormField<String>(
                        initialValue: toUserId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'พนักงานผู้รับมอบงานคนใหม่',
                          prefixIcon: Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 18,
                          ),
                        ),
                        items: availableUsers.map((u) {
                          return DropdownMenuItem<String>(
                            value: u.id,
                            child: Text(
                              '${u.displayName} (${u.department})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setCardState(() => toUserId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: isTransferring
                        ? null
                        : () async {
                            if (fromUserId == null || toUserId == null) return;
                            setCardState(() => isTransferring = true);
                            try {
                              final res = await ApiService.instance
                                  .adminHandoverChats(fromUserId!, toUserId!);
                              final count =
                                  res['transferred_rooms'] ??
                                  res['transferred_count'] ??
                                  res['rooms_count'] ??
                                  1;
                              final summary =
                                  (res['ai_briefing'] ??
                                          res['summary'] ??
                                          'โอนย้ายห้องแชทและส่งสรุปงานค้างด้วย DeepSeek AI เรียบร้อยแล้ว')
                                      .toString();
                              setCardState(() {
                                isTransferring = false;
                                handoverResultNote =
                                    '✅ โอนย้ายสำเร็จ $count ห้องแชท · $summary';
                              });
                              await _refreshConversationsAndFriends();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppTheme.brandDeep,
                                  content: Text(
                                    'โอนย้ายห้องแชทสำเร็จ ($count ห้อง) พร้อมส่ง AI Briefing เรียบร้อยแล้ว!',
                                  ),
                                ),
                              );
                            } catch (e) {
                              setCardState(() => isTransferring = false);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('โอนย้ายไม่สำเร็จ: $e')),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.workBlue,
                    ),
                    icon: isTransferring
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.published_with_changes_rounded,
                            size: 17,
                          ),
                    label: const Text(
                      'โอนย้ายห้องแชท & สร้างสรุปงานด้วย AI ทันที',
                    ),
                  ),
                ),
                if (handoverResultNote != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.brandSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      handoverResultNote!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brandDeep,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBroadcastCard() {
    final titleCtrl = TextEditingController(
      text: 'แจ้งอัปเดตระบบเสริม BC Super App ประจำสัปดาห์',
    );
    final contentCtrl = TextEditingController(
      text:
          'ขณะนี้ทีมงานได้เปิดใช้งานระบบเช็คสต็อกและใบเสนอราคาด่วนผ่านแท็บบริการเสริม สามารถกดใช้งานได้ทันทีครับ',
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.campaign_rounded, color: AppTheme.warningAmber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ส่งประกาศ Broadcast เข้าห้อง BC Official OA ถึงผู้ใช้ทุกคน',
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'หัวข้อประกาศ'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: contentCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ข้อความประกาศ'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                await ApiService.instance.sendAdminBroadcast(
                  title: titleCtrl.text,
                  content: contentCtrl.text,
                );
                await _refreshConversationsAndFriends();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.brandDeep,
                    content: Text(
                      'ส่งประกาศ Broadcast เข้าห้อง BC Official OA เรียบร้อยแล้ว!',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text('ส่งประกาศ Broadcast ทันที'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_rounded, color: AppTheme.workBlue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'รายชื่อผู้ใช้งานที่ซิงค์ด้วยบัญชี Gmail (User Management)',
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adminUsers.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (ctx, i) {
              final u = _adminUsers[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  name: u.displayName,
                  avatarUrl: u.avatarUrl,
                  radius: 19,
                ),
                title: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      u.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    PillBadge(
                      text: u.department,
                      backgroundColor: const Color(0xFFE0E7FF),
                      textColor: AppTheme.workBlue,
                    ),
                  ],
                ),
                subtitle: Text(
                  '${u.email} · BC ID: @${u.bcId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: PillBadge(
                  text: u.role.toUpperCase(),
                  backgroundColor: u.isAdmin
                      ? AppTheme.brandSoft
                      : AppTheme.surfaceBg,
                  textColor: u.isAdmin
                      ? AppTheme.brandDeep
                      : AppTheme.slateBody,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ThemePresetTile extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _ThemePresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Material(
      color: selected ? preset.soft : Colors.white,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? preset.primary : AppTheme.borderSubtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: preset.gradient),
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateDark,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      preset.suitsFor,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slateMuted,
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
    );
  }
}
