import 'dart:js_interop';

@JS('bcPushGetToken')
external JSPromise<JSString?> _bcPushGetToken(JSString configJson);

/// Web push token from window.bcPushGetToken (web/index.html); null when the
/// browser has no push or the user blocks notifications.
Future<String?> webPushToken(String configJson) async =>
    (await _bcPushGetToken(configJson.toJS).toDart)?.toDart;
