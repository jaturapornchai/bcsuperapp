/// Non-web builds: web push does not apply.
Future<String?> webPushToken(String configJson) async => null;

void Function(String conversationId)? _stubWebOpenListener;

void webPushListenOpens(void Function(String conversationId) open) {
  _stubWebOpenListener = open;
}

/// Forwards a simulated service-worker message in non-web VM tests.
void dispatchWebPushOpenForTest(String conversationId) {
  if (conversationId.isNotEmpty) {
    _stubWebOpenListener?.call(conversationId);
  }
}
