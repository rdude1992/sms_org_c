import 'package:flutter_test/flutter_test.dart';
import 'package:sms_organizer/utils/formatters.dart';

void main() {
  group('Formatters.muteUntil', () {
    final now = DateTime(2026, 11, 15, 10, 0);

    test('same day shows only the time', () {
      expect(Formatters.muteUntil(DateTime(2026, 11, 15, 18, 30), now: now), '6:30 PM');
    });

    test('another day shows the date too', () {
      expect(Formatters.muteUntil(DateTime(2026, 11, 22, 18, 30), now: now), '22 Nov, 6:30 PM');
    });
  });
}
