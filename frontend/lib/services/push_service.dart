import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'push_web_stub.dart' if (dart.library.js_interop) 'push_web.dart';

/// Alerts while the app is closed, through Firebase Cloud Messaging:
/// Android via MainActivity + BcPushService (channel bcapp/push), web via the
/// Firebase JS SDK in web/index.html + web/push_sw.js. The backend pushes only
/// to devices with no WebSocket open; other platforms get in-app alerts only.
class PushService {
  PushService._();
  static final PushService instance = PushService._();
  static const MethodChannel _android = MethodChannel('bcapp/push');
  static const String _prefApiBase = 'bcapp_api_base';

  String? _token;
  bool _webOpenTaken = false;
  void Function(String conversationId)? _onOpenConversation;

  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  void _bindAndroidHandler() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _android.setMethodCallHandler((call) async {
      final arg = call.arguments;
      if (call.method == 'openConversation' &&
          arg is String &&
          arg.isNotEmpty) {
        _onOpenConversation?.call(arg);
      } else if (call.method == 'onNewToken' &&
          arg is String &&
          arg.isNotEmpty) {
        _token = arg;
        await syncSettings();
      }
    });
  }

  /// After sign-in: get this install's token, listen for native token rotation,
  /// and save it with the alert settings. Does nothing when push is not set up.
  Future<void> start() async {
    if (!supported) return;
    try {
      _bindAndroidHandler();
      await NotificationService.instance.init();
      if (!kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefApiBase, ApiService.baseUrl);
        await ApiService.instance.deviceId();
      }
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
  /// each later tap while the app is in the background (Android) or in an
  /// already-open tab (web).
  Future<void> listenForOpens(
    void Function(String conversationId) open, {
    @visibleForTesting bool isWeb = kIsWeb,
    @visibleForTesting Uri? initialUri,
  }) async {
    _onOpenConversation = open;
    if (isWeb) {
      final uri = initialUri ?? Uri.base;
      final id = uri.queryParameters['conversation'];
      if (!_webOpenTaken && id != null && id.isNotEmpty) open(id);
      _webOpenTaken = true;
      webPushListenOpens(open);
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _bindAndroidHandler();
    try {
      final id = await _android.invokeMethod<String>('takeOpenedConversation');
      if (id != null && id.isNotEmpty) open(id);
    } catch (e) {
      debugPrint('push open failed: $e');
    }
  }
}
