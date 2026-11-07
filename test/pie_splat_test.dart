import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/pie_splat/pie_splat_3d.dart';
import 'package:oscar_games/games/pie_splat/pie_splat_game.dart';
import 'package:oscar_games/games/pie_splat/pie_splat_screen.dart';
import 'package:oscar_games/services/save_service.dart';

/// Runs about, throwing pies, until the round ends.
Future<PieSplatGameState> _playRound(WidgetTester tester, Size size) async {
  final state = tester.state<PieSplatGameState>(find.byType(PieSplatGameScreen));
  final start = Offset(size.width * 0.25, size.height * 0.6);
  final stick = await tester.startGesture(start);
  for (var t = 0; t < 2600; t++) {
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
  return state;
}

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
      Future<void> tap(Key key) async {
        await tester.ensureVisible(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byKey(key));
        for (var k = 0; k < 10; k++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tap(const Key('pie_play'));
      await tap(const Key('pie_start'));
      expect(find.byType(PieSplatGameScreen), findsOneWidget);

      final state = await _playRound(tester, size);
      expect(find.text('Play again'), findsOneWidget);
      expect(state.fighters.fold<int>(0, (n, g) => n + g.splats), greaterThan(3));

      await tester.tap(find.text('Play again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Play again'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  for (final setup in const [
    PieSetup(teams: 5, mode: PieMode.survival, difficulty: 2),
    PieSetup(teams: 2),
    PieSetup(players: 2, mode: PieMode.survival, difficulty: 0),
  ]) {
    testWidgets('${setup.teams} teams / ${setup.players} players ${setup.mode.name} plays out',
        (tester) async {
      const size = Size(390, 844);
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: PieSplatGameScreen(seed: 3, setup: setup)));
      final state = await _playRound(tester, size);
      expect(state.fighters.length, setup.fighters);
      if (setup.teams > 0) {
        expect(state.fighters.map((g) => g.team).toSet().length, setup.teams);
      }
      expect(state.guys.where((g) => g.kind == Kind.stranger), isNotEmpty);
      expect(find.text('Play again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
