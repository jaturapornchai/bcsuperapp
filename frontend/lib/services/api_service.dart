import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  static const String baseUrl = 'http://127.0.0.1:8095';
  static const String wsBaseUrl = 'ws://127.0.0.1:8095/ws';

  static const String _prefTokenKey = 'bcapp_jwt_token';
  static const String _prefUserKey = 'bcapp_user_json';
  static const String _prefChatThemeKey = 'bcapp_chat_theme';

  String? _token;
  AppUser? _currentUser;
  ChatRoomThemeMode _chatTheme = ChatRoomThemeMode.classicSky;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  final StreamController<Map<String, dynamic>> _wsController =
      StreamController<Map<String, dynamic>>.broadcast();

  String? get token => _token;
  AppUser? get currentUser => _currentUser;
  ChatRoomThemeMode get chatTheme => _chatTheme;
  Stream<Map<String, dynamic>> get wsEvents => _wsController.stream;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_prefTokenKey);
    _chatTheme = ChatRoomThemeMode.fromCode(
      prefs.getString(_prefChatThemeKey),
    );
    final rawUser = prefs.getString(_prefUserKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        _currentUser = AppUser.fromJson(
          jsonDecode(rawUser) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    if (_token != null && _token!.isNotEmpty) {
      try {
        final fresh = await fetchMe();
        if (fresh != null) {
          _currentUser = fresh;
          connectWebSocket();
          return true;
        }
      } catch (_) {
        if (_currentUser != null) {
          connectWebSocket();
          return true;
        }
      }
    }
    return false;
  }

  Future<void> setChatTheme(ChatRoomThemeMode mode) async {
    _chatTheme = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefChatThemeKey, mode.code);
  }

  Future<void> _saveAuth(String token, AppUser user) async {
    _token = token;
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTokenKey, token);
    await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
  }

  Future<void> logout() async {
    disconnectWebSocket();
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefTokenKey);
    await prefs.remove(_prefUserKey);
  }

  void connectWebSocket() {
    disconnectWebSocket();
    final jwt = _token;
    if (jwt == null || jwt.isEmpty) return;

    try {
      final uri = Uri.parse('$wsBaseUrl?token=${Uri.encodeComponent(jwt)}');
      _wsChannel = WebSocketChannel.connect(uri);
      _wsSub = _wsChannel!.stream.listen(
        (raw) {
          if (raw is String && raw.isNotEmpty) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map<String, dynamic>) {
                _wsController.add(decoded);
              } else if (decoded is Map) {
                _wsController.add(Map<String, dynamic>.from(decoded));
              }
            } catch (_) {}
          }
        },
        onError: (_) {},
        onDone: () {},
      );
    } catch (_) {}
  }

  void disconnectWebSocket() {
    _wsSub?.cancel();
    _wsSub = null;
    try {
      _wsChannel?.sink.close();
    } catch (_) {}
    _wsChannel = null;
  }

  String resolveMiniAppUrl(MiniAppItem app) {
    final jwt = Uri.encodeComponent(_token ?? '');
    if (app.url.startsWith('http://') || app.url.startsWith('https://')) {
      final separator = app.url.contains('?') ? '&' : '?';
      return '${app.url}${separator}token=$jwt';
    }
    final path = app.url.isNotEmpty ? app.url : '/miniapp/${app.code}';
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final separator = normalizedPath.contains('?') ? '&' : '?';
    return '$baseUrl$normalizedPath${separator}token=$jwt';
  }

  // ---------------------------------------------------------------------------
  // 1-3. Authentication & Profile
  // ---------------------------------------------------------------------------
  Future<AppUser> loginWithGoogle({
    required String email,
    required String displayName,
    String? avatarUrl,
    String? googleId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/google'),
      headers: _headers,
      body: jsonEncode({
        'email': email.trim(),
        'display_name': displayName.trim(),
        'avatar_url': avatarUrl ?? '',
        'google_id': googleId ?? 'google_${email.trim().hashCode.abs()}',
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('เข้าสู่ระบบไม่สำเร็จ (${res.statusCode}): ${res.body}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final token = (data['token'] ?? '').toString();
    final userMap = (data['user'] ?? data) as Map<String, dynamic>;
    final user = AppUser.fromJson(userMap);
    await _saveAuth(token, user);
    connectWebSocket();
    return user;
  }

  Future<AppUser?> fetchMe() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _headers,
    );
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['user'] is Map<String, dynamic>
              ? decoded['user'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    final user = AppUser.fromJson(map);
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
    return user;
  }

  Future<AppUser> updateProfile({
    required String displayName,
    required String bcId,
    required String statusMessage,
    String? avatarUrl,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/auth/profile'),
      headers: _headers,
      body: jsonEncode({
        'display_name': displayName.trim(),
        'bc_id': bcId.trim(),
        'status_message': statusMessage.trim(),
        'avatar_url': avatarUrl ?? _currentUser?.avatarUrl ?? '',
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('อัปเดตโปรไฟล์ไม่สำเร็จ: ${utf8.decode(res.bodyBytes)}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['user'] is Map<String, dynamic>
              ? decoded['user'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    final user = AppUser.fromJson(map);
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
    return user;
  }

  // ---------------------------------------------------------------------------
  // 4-6. Friends & Search
  // ---------------------------------------------------------------------------
  Future<List<AppUser>> fetchFriends() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/friends'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['friends'] is List
              ? decoded['friends'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AppUser>> searchUsers(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final res = await http.get(
      Uri.parse('$baseUrl/api/users/search?q=$q'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['users'] is List
              ? decoded['users'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> addFriend({
    String? targetId,
    String? bcId,
    String? email,
    String? qrToken,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/friends/add'),
      headers: _headers,
      body: jsonEncode({
        if (targetId != null && targetId.isNotEmpty) 'target_id': targetId,
        if (bcId != null && bcId.isNotEmpty) 'bc_id': bcId,
        if (email != null && email.isNotEmpty) 'email': email,
        if (qrToken != null && qrToken.isNotEmpty) 'qr_token': qrToken,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ไม่พบผู้ใช้หรือไม่สามารถเพิ่มเพื่อนได้');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // 7-11. Conversations
  // ---------------------------------------------------------------------------
  Future<List<Conversation>> fetchConversations({String folder = 'all'}) async {
    final res = await http.get(
      Uri.parse(
        '$baseUrl/api/conversations?folder=${Uri.encodeQueryComponent(folder)}',
      ),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['conversations'] is List
              ? decoded['conversations'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Conversation> openDirectConversation(String friendId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/direct'),
      headers: _headers,
      body: jsonEncode({'friend_id': friendId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ไม่สามารถเปิดห้องแชทได้');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['conversation'] is Map<String, dynamic>
              ? decoded['conversation'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return Conversation.fromJson(map);
  }

  Future<Conversation> createGroupConversation({
    required String name,
    required String folder,
    required List<String> memberIds,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/group'),
      headers: _headers,
      body: jsonEncode({
        'name': name.trim(),
        'folder': folder,
        'member_ids': memberIds,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ไม่สามารถสร้างกลุ่มได้');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['conversation'] is Map<String, dynamic>
              ? decoded['conversation'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return Conversation.fromJson(map);
  }

  Future<Conversation?> updateConversationMeta(
    String conversationId, {
    String? folder,
    bool? isPinned,
    String? name,
  }) async {
    final payload = <String, dynamic>{
      'folder': ?folder,
      'is_pinned': ?isPinned,
      'name': ?name,
    };
    final res = await http.put(
      Uri.parse('$baseUrl/api/conversations/$conversationId/meta'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final target = decoded['conversation'] is Map<String, dynamic>
          ? decoded['conversation'] as Map<String, dynamic>
          : decoded;
      return Conversation.fromJson(target);
    }
    return null;
  }

  Future<void> pinConversationMessage(
    String conversationId,
    String? messageId,
  ) async {
    await http.put(
      Uri.parse('$baseUrl/api/conversations/$conversationId/pin-message'),
      headers: _headers,
      body: jsonEncode({'message_id': messageId ?? ''}),
    );
  }

  // ---------------------------------------------------------------------------
  // 12-17. Messages, Read Receipts, Unsend, Vault & Global Search
  // ---------------------------------------------------------------------------
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/conversations/$conversationId/messages'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['messages'] is List
              ? decoded['messages'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ChatMessage> sendMessage(
    String conversationId, {
    required String type,
    required String content,
    String? stickerCode,
    AttachmentInfo? attachment,
    Map<String, dynamic>? flexPayload,
    String? replyToId,
    bool isConfidential = false,
  }) async {
    final effectiveFlex = flexPayload != null
        ? {...flexPayload, if (isConfidential) 'is_confidential': true}
        : (isConfidential ? <String, dynamic>{'is_confidential': true} : null);

    final effectiveContent =
        isConfidential && !content.startsWith('[ลับเฉพาะองค์กร]')
        ? '[ลับเฉพาะองค์กร] $content'
        : content;

    final attachmentJson = attachment?.toJson();
    final res = await http.post(
      Uri.parse('$baseUrl/api/conversations/$conversationId/messages'),
      headers: _headers,
      body: jsonEncode({
        'type': type,
        'content': effectiveContent,
        'is_confidential': isConfidential,
        'sticker_code': ?stickerCode,
        'attachment': ?attachmentJson,
        'flex_payload': ?effectiveFlex,
        if (replyToId != null && replyToId.isNotEmpty)
          'reply_to_id': replyToId,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ส่งข้อความไม่สำเร็จ (${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['message'] is Map<String, dynamic>
              ? decoded['message'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return ChatMessage.fromJson(map);
  }

  Future<void> markConversationRead(String conversationId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/conversations/$conversationId/read'),
        headers: _headers,
      );
    } catch (_) {}
  }

  Future<void> unsendMessage(String messageId, {bool hard = false}) async {
    final suffix = hard ? '?hard=true' : '';
    await http.delete(
      Uri.parse('$baseUrl/api/messages/$messageId/unsend$suffix'),
      headers: _headers,
    );
  }

  Future<VaultData> fetchVault(String conversationId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/conversations/$conversationId/vault'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      return const VaultData(images: [], files: [], links: []);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return VaultData.fromJson(decoded);
    }
    return const VaultData(images: [], files: [], links: []);
  }

  Future<List<ChatMessage>> searchMessages(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final res = await http.get(
      Uri.parse('$baseUrl/api/messages/search?q=$q'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['messages'] is List
              ? decoded['messages'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // 18. Keep & Room Notes
  // ---------------------------------------------------------------------------
  Future<List<NoteItem>> fetchNotes({String? conversationId}) async {
    final uri = conversationId != null && conversationId.isNotEmpty
        ? Uri.parse(
            '$baseUrl/api/notes?conversation_id=${Uri.encodeQueryComponent(conversationId)}',
          )
        : Uri.parse('$baseUrl/api/notes');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['notes'] is List
              ? decoded['notes'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<NoteItem> createNote({
    String? conversationId,
    required String title,
    required String content,
    String category = 'บันทึกสำคัญ',
    String color = '#06C755',
    AttachmentInfo? attachment,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/notes'),
      headers: _headers,
      body: jsonEncode({
        if (conversationId != null && conversationId.isNotEmpty)
          'conversation_id': conversationId,
        'title': title.trim(),
        'content': content.trim(),
        'category': category,
        'color': color,
        if (attachment != null) 'attachment': attachment.toJson(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('สร้างโน้ตไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['note'] is Map<String, dynamic>
              ? decoded['note'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return NoteItem.fromJson(map);
  }

  Future<void> deleteNote(String noteId) async {
    await http.delete(
      Uri.parse('$baseUrl/api/notes/$noteId'),
      headers: _headers,
    );
  }

  // ---------------------------------------------------------------------------
  // 19. MinIO Permanent File Upload
  // ---------------------------------------------------------------------------
  Future<AttachmentInfo> uploadFileBase64({
    required String fileName,
    required String mimeType,
    required String dataBase64,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/upload'),
      headers: _headers,
      body: jsonEncode({
        'file_name': fileName,
        'mime_type': mimeType,
        'data_base64': dataBase64,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('อัปโหลดไฟล์เข้า MinIO ไม่สำเร็จ (${res.statusCode})');
    }
    final decoded =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return AttachmentInfo.fromJson(decoded);
  }

  // ---------------------------------------------------------------------------
  // 20-24. Mini-Apps & Admin Backoffice
  // ---------------------------------------------------------------------------
  Future<List<MiniAppItem>> fetchMiniApps() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/mini-apps'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['mini_apps'] is List
              ? decoded['mini_apps'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => MiniAppItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AdminOverview?> fetchAdminOverview() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/overview'),
      headers: _headers,
    );
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AdminOverview.fromJson(decoded);
    }
    return null;
  }

  Future<List<AppUser>> fetchAdminUsers() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/users'),
      headers: _headers,
    );
    if (res.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['users'] is List
              ? decoded['users'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> updateUserRole(String userId, String role) async {
    await http.put(
      Uri.parse('$baseUrl/api/admin/users/$userId/role'),
      headers: _headers,
      body: jsonEncode({'role': role}),
    );
  }

  Future<List<MiniAppItem>> fetchAdminMiniApps() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/mini-apps'),
      headers: _headers,
    );
    if (res.statusCode != 200) return fetchMiniApps();
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['mini_apps'] is List
              ? decoded['mini_apps'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => MiniAppItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<MiniAppItem> createAdminMiniApp(Map<String, dynamic> payload) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/mini-apps'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('เพิ่มระบบเสริมไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['mini_app'] is Map<String, dynamic>
              ? decoded['mini_app'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return MiniAppItem.fromJson(map);
  }

  Future<MiniAppItem> updateAdminMiniApp(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/admin/mini-apps/$id'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('แก้ไขระบบเสริมไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic>
        ? (decoded['mini_app'] is Map<String, dynamic>
              ? decoded['mini_app'] as Map<String, dynamic>
              : decoded)
        : <String, dynamic>{};
    return MiniAppItem.fromJson(map);
  }

  Future<void> deleteAdminMiniApp(String id) async {
    await http.delete(
      Uri.parse('$baseUrl/api/admin/mini-apps/$id'),
      headers: _headers,
    );
  }

  Future<void> sendAdminBroadcast({
    required String title,
    required String content,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/broadcast'),
      headers: _headers,
      body: jsonEncode({'title': title.trim(), 'content': content.trim()}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ส่งประกาศ Broadcast ไม่สำเร็จ');
    }
  }

  // ---------------------------------------------------------------------------
  // 25-28. DeepSeek AI Brain (Summarize, Assist, @ai Group Brain, Admin Settings)
  // ---------------------------------------------------------------------------
  Future<AiSummaryResult> summarizeConversation(String conversationId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/ai/summarize'),
      headers: _headers,
      body: jsonEncode({'conversation_id': conversationId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'ไม่สามารถสรุปห้องแชทด้วย AI ได้ (${res.statusCode}): ${utf8.decode(res.bodyBytes)}',
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiSummaryResult.fromJson(decoded);
    }
    return AiSummaryResult(
      summary: decoded.toString(),
      actionItems: const [],
      decisions: const [],
      model: 'deepseek-chat',
    );
  }

  Future<AiAssistResult> requestAiAssist({
    required String conversationId,
    required String mode,
    required String text,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/ai/assist'),
      headers: _headers,
      body: jsonEncode({
        'conversation_id': conversationId,
        'mode': mode,
        'text': text.trim(),
        'prompt': text.trim(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'เรียกสมองกล DeepSeek AI ไม่สำเร็จ (${res.statusCode}): ${utf8.decode(res.bodyBytes)}',
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiAssistResult.fromJson(decoded);
    }
    return AiAssistResult(
      suggestion: decoded.toString(),
      alternatives: const [],
      mode: mode,
      model: 'deepseek-chat',
    );
  }

  Future<AiAdminSettings> fetchAdminAiSettings() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/admin/ai-settings'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      return const AiAdminSettings(
        model: 'deepseek-chat',
        maskedKey: 'ตั้งค่าบนเซิร์ฟเวอร์เรียบร้อย',
        hasKey: true,
        systemPrompt:
            'คุณคือสมองกลอัจฉริยะ BC DeepSeek AI ประจำองค์กรและทุกกลุ่มแชท ช่วยสรุปงาน วิเคราะห์ข้อมูลธุรกิจ ฝ่ายขาย บัญชีการเงิน และช่วยเกลาข้อความอย่างมืออาชีพ',
        enabled: true,
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiAdminSettings.fromJson(decoded);
    }
    return const AiAdminSettings(
      model: 'deepseek-chat',
      maskedKey: 'ตั้งค่าบนเซิร์ฟเวอร์เรียบร้อย',
      hasKey: true,
      systemPrompt: '',
      enabled: true,
    );
  }

  Future<AiAdminSettings> updateAdminAiSettings({
    required String model,
    String? apiKey,
    required String systemPrompt,
    bool enabled = true,
  }) async {
    final cleanKey = apiKey?.trim();
    final res = await http.put(
      Uri.parse('$baseUrl/api/admin/ai-settings'),
      headers: _headers,
      body: jsonEncode({
        'model': model,
        if (cleanKey != null && cleanKey.isNotEmpty) 'api_key': cleanKey,
        'system_prompt': systemPrompt.trim(),
        'enabled': enabled,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('บันทึกตั้งค่า DeepSeek AI ไม่สำเร็จ');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return AiAdminSettings.fromJson(decoded);
    }
    return fetchAdminAiSettings();
  }
}
