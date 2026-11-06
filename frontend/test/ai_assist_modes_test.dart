import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // /api/ai/assist picks its instruction by mode; an unknown code makes the AI
  // answer the raw draft instead of polishing it (was 'polite'/'smart_reply').
  test('every assist mode in the dialog is one the backend handles', () {
    final ui = File('lib/screens/chat_room_screen.dart').readAsStringSync();
    final start = ui.indexOf('_modes = [');
    expect(start, isNot(-1));
    final block = ui.substring(start, ui.indexOf('];', start));
    final codes = {
      ...RegExp(r"\('(\w+)',").allMatches(block).map((m) => m[1]!),
      ...RegExp(r"initialMode: '(\w+)'").allMatches(ui).map((m) => m[1]!),
    };
    expect(codes, isNotEmpty);
    final rs = File('../backend/src/routes/ai_routes.rs').readAsStringSync();
    for (final c in codes) {
      expect(rs.contains('"$c" =>') || rs.contains('"$c" |'), isTrue,
          reason: 'backend has no assist mode $c');
    }
  });

  // Picking a mode chip re-runs the AI while an earlier call may still be in
  // flight; the slower earlier reply used to overwrite the newer answer.
  test('assist dialog drops replies from superseded runs', () {
    final ui = File('lib/screens/chat_room_screen.dart').readAsStringSync();
    final start = ui.indexOf('Future<void> _runAssist()');
    expect(start, isNot(-1));
    final body = ui.substring(start, ui.indexOf('Widget build', start));
    expect(body, contains('final seq = ++_runSeq;'));
    expect(RegExp(r'seq != _runSeq\) return;').allMatches(body).length, 2,
        reason: 'both the success and the error branch must ignore stale runs');
  });

  // The handover card read keys the backend never sent, so it always showed
  // "1 ห้อง" and claimed an AI briefing even when DeepSeek was off.
  test('handover result keys match the backend response', () {
    final ui = File('lib/screens/main_shell.dart').readAsStringSync();
    final rs = File('../backend/src/routes/admin_routes.rs').readAsStringSync();
    for (final k in ['transferred_conversations', 'ai_briefed']) {
      expect(ui.contains("res['$k']"), isTrue, reason: 'UI does not read $k');
      expect(rs.contains('"$k":'), isTrue, reason: 'backend does not send $k');
    }
  });
}
