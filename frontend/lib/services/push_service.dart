import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'push_web_stub.dart' if (dart.library.js_interop) 'push_web.dart';

/// Alerts while the app is closed, through Firebase Cloud Messaging:
/// Android via MainActivity (channel bcapp/push), web via the Firebase JS SDK
/// in web/index.html + web/push_sw.js. The backend pushes only to devices
/// with no WebSocket open; other platforms get in-app alerts only.
class PushService {
  PushService._();
  static final PushService instance = PushService._();
  static const MethodChannel _android = MethodChannel('bcapp/push');

  String? _token;
  bool _webOpenTaken = false;

  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// After sign-in: get this install's token and save it with the alert
  /// settings. Does nothing when push is not set up (no Firebase config).
  // ponytail: token is re-read on every start instead of a native
  // onNewToken hook; a rotated token is picked up on the next app open.
  Future<void> start() async {
    if (!supported) return;
    try {
      await NotificationService.instance.init();
      _token = await _fetchToken();
      await syncSettings();
    } catch (e) {
      debugPrint('push start failed: $e');
    }
  }

  /// Sends the current alert settings (pop-up, sound per kind) with the token.
  Future<void> syncSettings() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    final n = NotificationService.instance;
    try {
      await ApiService.instance.registerDevice({
        'token': token,
        'platform': kIsWeb ? 'web' : 'android',
        'popup': n.popupEnabled,
        'sound': n.soundEnabled,
        'sounds': {for (final k in AlertKind.values) k.name: n.soundOf(k)},
      });
    } catch (e) {
      debugPrint('push sync failed: $e');
    }
  }

  Future<String?> _fetchToken() async {
    if (kIsWeb) {
      final web = (await ApiService.instance.fetchPushConfig())['web'];
      return web is Map ? webPushToken(jsonEncode(web)) : null;
    }
    await NotificationService.instance.createPushChannels();
    return _android.invokeMethod<String>('getToken');
  }

  /// Opens the room of a tapped push: the one the app was started with, then
  /// each later tap while the app is in the background (Android).
  Future<void> listenForOpens(void Function(String conversationId) open) async {
    if (kIsWeb) {
      final id = Uri.base.queryParameters['conversation'];
      if (!_webOpenTaken && id != null && id.isNotEmpty) open(id);
      _webOpenTaken = true;
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _android.setMethodCallHandler((call) async {
      final id = call.arguments;
      if (call.method == 'openConversation' && id is String) open(id);
    });
    try {
      final id = await _android.invokeMethod<String>('takeOpenedConversation');
      if (id != null && id.isNotEmpty) open(id);
    } catch (e) {
      debugPrint('push open failed: $e');
    }
  }
}
