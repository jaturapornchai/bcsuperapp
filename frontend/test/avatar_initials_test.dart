import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_theme.dart';

void main() {
  test('avatar initials never show dangling Thai marks or brackets', () {
    expect(avatarInitials('ลุงจืด (Super Admin)'), 'ล');
    expect(avatarInitials('ลุงจืด (ผู้บริหาร)'), 'ลผ');
    expect(avatarInitials('สมชาย ฝ่ายขาย'), 'สฝ');
    expect(avatarInitials('นิดา บัญชีการเงิน'), 'นบ');
    expect(avatarInitials('ห้องประชุมความลับผู้บริหาร E2E'), 'ห');
    expect(avatarInitials('เจด ใจดี'), 'จจ');
    expect(avatarInitials('BC Official OA'), 'BO');
    expect(avatarInitials('🤖 BC AI'), 'BA');
    expect(avatarInitials('   '), 'BC');
  });
}
