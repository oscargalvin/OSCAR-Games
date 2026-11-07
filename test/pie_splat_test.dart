import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/pie_splat/pie_splat_game.dart';
import 'package:oscar_games/games/pie_splat/pie_splat_screen.dart';
import 'package:oscar_games/services/save_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SaveService.instance.init();
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets('a whole round of Pie Splat plays out on $size', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: PieSplatScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byKey(const Key('pie_play')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('pie_play')));
      for (var k = 0; k < 10; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(PieSplatGameScreen), findsOneWidget);

      // Tap all over the place for longer than a round lasts.
      var i = 0;
      for (var t = 0; t < 1500; t++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (t % 3 == 0 && find.text('Play again').evaluate().isEmpty) {
          final x = size.width * (0.1 + 0.8 * ((i * 37) % 100) / 100);
          final y = size.height * (0.2 + 0.7 * ((i * 53) % 100) / 100);
          await tester.tapAt(Offset(x, y));
          i++;
        }
      }
      expect(find.text('Play again'), findsOneWidget);
      final score = SaveService.instance.getHighScore(kPieSplatId);
      expect(score, greaterThan(0));

      await tester.tap(find.text('Play again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Play again'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
