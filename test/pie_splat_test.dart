import 'dart:math';

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

      // Run about and throw pies for longer than a round lasts.
      final state = tester.state<PieSplatGameState>(find.byType(PieSplatGameScreen));
      final start = Offset(size.width * 0.25, size.height * 0.6);
      final stick = await tester.startGesture(start);
      for (var t = 0; t < 2000; t++) {
        if (t % 40 == 0) {
          final a = t / 40.0;
          await stick.moveTo(start + Offset(cos(a) * 40, sin(a * 1.3) * 40));
        }
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Play again').evaluate().isNotEmpty) break;
        if (t % 4 == 0) state.throwPie();
        if (t % 50 == 0) state.dodge();
      }
      await stick.up();
      for (var k = 0; k < 20; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.fighters.fold<int>(0, (n, g) => n + g.splats), greaterThan(3));
      expect(find.text('Play again'), findsOneWidget);

      await tester.tap(find.text('Play again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Play again'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
