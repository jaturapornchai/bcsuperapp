import 'dart:js_interop';

@JS('bcPushGetToken')
external JSPromise<JSString?> _bcPushGetToken(JSString configJson);

@JS('bcPushListenOpens')
external void _bcPushListenOpens(JSFunction onOpen);

/// Web push token from window.bcPushGetToken (web/index.html); null when the
/// browser has no push or the user blocks notifications.
Future<String?> webPushToken(String configJson) async =>
    (await _bcPushGetToken(configJson.toJS).toDart)?.toDart;

/// Listens for notification taps forwarded by push_sw.js to an open tab.
void webPushListenOpens(void Function(String conversationId) open) {
  _bcPushListenOpens(
    ((JSString id) {
      final convId = id.toDart;
      if (convId.isNotEmpty) open(convId);
    }).toJS,
  );
}
