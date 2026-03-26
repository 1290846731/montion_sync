import 'package:flutter_test/flutter_test.dart';

import 'package:strava_sync/utils/parsing.dart';

void main() {
  test('safeFilename sanitizes invalid characters', () {
    expect(safeFilename('a/b:c'), 'a_b_c');
    expect(safeFilename('   '), 'activity');
  });
}

