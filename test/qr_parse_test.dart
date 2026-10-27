// Proves ScannedSetup.tryParse handles every real QR shape the server emits.
// Run: flutter test test/qr_parse_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taptosay/qr_scan_screen.dart';

void main() {
  // Verbatim shape from src/routes/tablets.js (student tablet).
  const studentQr = '{"android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME":'
      '"app.taptosay/.TapToSayDeviceAdminReceiver",'
      '"android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM":"abc123",'
      '"android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION":'
      '"https://taptosay.app/download/x.apk",'
      '"android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE":{'
      '"server_url":"https://api.taptosay.app","tablet_id":"1",'
      '"student_id":"43162","school_tea_id":"237904104",'
      '"auth_password":"t3jf-b8qe-84h6-9xbb"}}';

  // Teacher QR: presents her T-code as student_id, per src/routes/users.js.
  const teacherQr = '{"android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE":{'
      '"server_url":"https://api.taptosay.app","tablet_id":"2",'
      '"student_id":"T82711","school_tea_id":"237904","auth_password":"a1b2c3d4e5f6"}}';

  test('parses a student tablet QR', () {
    final s = ScannedSetup.tryParse(studentQr);
    expect(s, isNotNull);
    expect(s!.schoolId, '237904104');
    expect(s.studentId, '43162');
    expect(s.authPassword, 't3jf-b8qe-84h6-9xbb');
    expect(s.serverUrl, 'https://api.taptosay.app');
  });

  test('parses a teacher QR (T-code arrives as student_id)', () {
    final s = ScannedSetup.tryParse(teacherQr);
    expect(s, isNotNull);
    expect(s!.studentId, 'T82711');
    expect(s.schoolId, '237904');
    expect(s.authPassword, 'a1b2c3d4e5f6');
  });

  test('accepts a bare extras object', () {
    const bare = '{"server_url":"https://api.taptosay.app","student_id":"43162",'
        '"school_tea_id":"237904104","auth_password":"pw"}';
    final s = ScannedSetup.tryParse(bare);
    expect(s, isNotNull);
    expect(s!.studentId, '43162');
    expect(s.authPassword, 'pw');
  });

  test('accepts a URL with query parameters (hand-printed setup)', () {
    const u = 'https://api.taptosay.app/setup?server_url=https://api.taptosay.app'
        '&student_id=43162&school_tea_id=237904104&auth_password=pw';
    final s = ScannedSetup.tryParse(u);
    expect(s, isNotNull);
    expect(s!.studentId, '43162');
    expect(s.schoolId, '237904104');
  });

  test('ignores surrounding whitespace', () {
    final s = ScannedSetup.tryParse('  $studentQr\n');
    expect(s, isNotNull);
    expect(s!.studentId, '43162');
  });

  test('rejects unrelated QR content with an explanation', () {
    String? why;
    final s = ScannedSetup.tryParse('https://example.com/menu',
        onError: (m) => why = m);
    expect(s, isNull);
    expect(why, isNotNull);
    expect(why, contains('TapToSay'));
  });

  test('rejects empty input', () {
    String? why;
    final s = ScannedSetup.tryParse('   ', onError: (m) => why = m);
    expect(s, isNull);
    expect(why, isNotNull);
  });

  test('rejects malformed JSON', () {
    final s = ScannedSetup.tryParse('{not json at all');
    expect(s, isNull);
  });
}
