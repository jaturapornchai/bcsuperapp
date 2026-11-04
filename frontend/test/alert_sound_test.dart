import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/services/notification_service.dart';

void main() {
  test('every sound choice has its asset file', () {
    for (final s in NotificationService.sounds) {
      if (s.code == NotificationService.noSound) continue;
      expect(File('assets/sounds/${s.code}.wav').existsSync(), isTrue,
          reason: s.code);
    }
    final codes = NotificationService.sounds.map((s) => s.code).toSet();
    for (final k in AlertKind.values) {
      expect(codes, contains(k.defaultSound), reason: k.name);
    }
  });

  test('urgent beats AI, AI beats normal', () {
    ChatMessage m(String sender, String priority) => ChatMessage.fromJson({
      'id': 'm', 'conversation_id': 'c', 'sender_id': sender,
      'sender_name': 'x', 'type': 'text', 'content': 'hi',
      'priority': priority,
    });
    expect(NotificationService.kindOf(m('u1', 'normal')), AlertKind.normal);
    expect(NotificationService.kindOf(m('user_ai', 'normal')), AlertKind.ai);
    expect(NotificationService.kindOf(m('user_ai', 'urgent')), AlertKind.urgent);
  });
}
