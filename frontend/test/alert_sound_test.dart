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
      // Push channels (push_<code>) play the Android copy.
      expect(
          File('android/app/src/main/res/raw/alert_${s.code}.wav')
              .existsSync(),
          isTrue,
          reason: 'raw ${s.code}');
    }
    // The backend only accepts codes it knows (SOUND_CODES in push.rs).
    final pushRs = File('../backend/src/push.rs').readAsStringSync();
    for (final s in NotificationService.sounds) {
      final known = s.code == NotificationService.noSound
          ? pushRs.contains('NO_SOUND: &str = "none"')
          : pushRs.contains('"${s.code}"');
      expect(known, isTrue, reason: 'backend SOUND_CODES lacks ${s.code}');
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
