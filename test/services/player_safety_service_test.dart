import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/player_safety_service.dart';

// reportPlayer refuses any reason outside PLAYER_REPORT_REASONS
// (functions/src/player_safety.ts), so the app's list has to match it
// exactly or a report fails with "Invalid report".
void main() {
  test('los motivos de reporte coinciden con los del servidor', () {
    expect(
      PlayerReportReason.values.map((r) => r.id).toSet(),
      {'offensive_name', 'cheating', 'spam_or_harassment', 'other'},
    );
  });
}
