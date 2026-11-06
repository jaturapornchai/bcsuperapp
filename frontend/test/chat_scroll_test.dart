import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _body(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNot(-1), reason: 'missing $signature');
  return src.substring(start, src.indexOf('\n  }\n', start));
}

void main() {
  final ui = File('lib/screens/chat_room_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  // Opening a long room stopped short of the newest message: the first
  // maxScrollExtent of a ListView.builder is only an estimate.
  test('scroll to bottom keeps chasing a growing scroll extent', () {
    final body = _body(ui, 'void _scrollToBottom()');
    expect(body, contains('for ('));
    expect(body, contains('maxScrollExtent <= target'));
  });

  // Replies from others (AI answers, handover briefings) landed below the fold.
  test('quiet refresh follows new messages when the reader is at the end', () {
    final body = _body(ui, 'Future<void> _refreshMessagesQuietly()');
    expect(body, contains('extentAfter'));
    expect(body, contains('_scrollToBottom()'));
  });
}
