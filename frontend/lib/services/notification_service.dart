import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';

/// OS pop-up alert (sender + preview + system sound) for incoming chat
/// messages while the app is running. Fed by MainShell's WebSocket listener;
/// tapping a pop-up opens that room.
// ponytail: no push when the app is closed — that needs FCM/APNs credentials.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Room currently on screen (set by ChatRoomScreen); its messages do not
  /// pop up while the app window is in front.
  String? openConversationId;

  /// Called with the conversation id when the user taps a pop-up.
  void Function(String conversationId)? onOpenConversation;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          windows: WindowsInitializationSettings(
            appName: 'BC Super App',
            appUserModelId: 'BCSuperApp.Chat',
            guid: '5566db43-a2fd-4bf8-8ec4-282206ed3d94',
          ),
          web: WebInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) {
          final id = response.payload;
          if (id != null && id.isNotEmpty) onOpenConversation?.call(id);
        },
      );
      await _requestPermission();
    } catch (e) {
      debugPrint('notification init failed: $e');
    }
  }

  Future<void> _requestPermission() async {
    if (kIsWeb) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    // iOS/macOS ask on initialize (DarwinInitializationSettings defaults).
  }

  /// Shows a pop-up for a `new_message` WebSocket event when it should alert.
  Future<void> handleWsEvent(
    Map<String, dynamic> event, {
    required String myUserId,
    Conversation? room,
  }) async {
    if (event['event'] != 'new_message' || event['message'] is! Map) return;
    final msg = ChatMessage.fromJson(
      Map<String, dynamic>.from(event['message'] as Map),
    );
    final appInFront =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (appInFront && msg.conversationId == openConversationId) return;
    final alert = describe(msg, myUserId: myUserId, room: room);
    if (alert == null || !_initialized) return;

    final silent = msg.priority == 'silent';
    try {
      await _plugin.show(
        // One pop-up per room: a newer message replaces the older one.
        id: msg.conversationId.hashCode & 0x7fffffff,
        title: alert.title,
        body: alert.body,
        payload: msg.conversationId,
        notificationDetails: NotificationDetails(
          android: silent
              ? const AndroidNotificationDetails(
                  'chat_silent',
                  'ข้อความแบบไม่มีเสียง',
                  channelDescription: 'ข้อความที่ผู้ส่งเลือกส่งแบบเงียบ',
                  importance: Importance.low,
                  priority: Priority.low,
                  playSound: false,
                )
              : const AndroidNotificationDetails(
                  'chat_messages',
                  'ข้อความแชท',
                  channelDescription: 'แจ้งเตือนเมื่อมีข้อความใหม่',
                  importance: Importance.high,
                  priority: Priority.high,
                  category: AndroidNotificationCategory.message,
                ),
          iOS: DarwinNotificationDetails(presentSound: !silent),
          macOS: DarwinNotificationDetails(presentSound: !silent),
          windows: WindowsNotificationDetails(
            audio: silent ? WindowsNotificationAudio.silent() : null,
          ),
          web: WebNotificationDetails(isSilent: silent, renotify: true),
        ),
      );
    } catch (e) {
      debugPrint('notification show failed: $e');
    }
  }

  /// Title/body for a message, or null when it should not alert
  /// (own message, system notice, unsent).
  static ({String title, String body})? describe(
    ChatMessage msg, {
    required String myUserId,
    Conversation? room,
  }) {
    if (msg.senderId == myUserId || msg.type == 'system' || msg.isUnsent) {
      return null;
    }
    final String preview;
    if (msg.isConfidential) {
      preview = 'ส่งข้อความลับ 🔒';
    } else {
      switch (msg.type) {
        case 'image':
          preview = 'ส่งรูปภาพ';
        case 'file':
          final name = msg.attachment?.fileName ?? '';
          preview = name.isEmpty ? 'ส่งไฟล์' : 'ส่งไฟล์ $name';
        case 'sticker':
          preview = 'ส่งสติกเกอร์';
        case 'flex_card':
          preview = 'ส่งการ์ด';
        default:
          final text = msg.content.trim();
          preview = text.length > 120 ? '${text.substring(0, 120)}…' : text;
      }
    }
    final body = msg.priority == 'urgent' ? '⚡ ด่วน: $preview' : preview;
    final isGroup = room != null && room.kind != 'direct';
    return isGroup
        ? (title: room.name, body: '${msg.senderName}: $body')
        : (title: msg.senderName, body: body);
  }
}
