import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String src(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  // "บันทึกเข้า BC Keep" saved only a room note, but BC Keep lists notes that
  // have no room, so the AI summary never showed up there.
  test('saving an AI summary also creates a personal BC Keep note', () {
    final ui = src('lib/screens/chat_room_screen.dart');
    final start = ui.indexOf('onSaveToKeep:');
    expect(start, isNot(-1));
    final body = ui.substring(start, ui.indexOf('showSnackBar', start));
    expect(body, contains('[_conversation.id, null]'));
  });

  // The Keep list was fetched once at start-up, so notes saved later were
  // missing until the app reloaded.
  test('opening the BC Keep tab reloads its notes', () {
    final ui = src('lib/screens/main_shell.dart');
    expect(
      'if (idx == 3) _reloadKeepNotes();'.allMatches(ui).length,
      2,
      reason: 'both the bottom bar and the side rail must reload',
    );
  });
}
