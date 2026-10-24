import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/boost_ball/boost_ball_data.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_game.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_screen.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_sim.dart';

BoostBallMatch _botMatch(int size, int level, int seed) {
  final cars = [
    for (var team = 0; team < 2; team++)
      for (var i = 0; i < size; i++)
        Car(
          team: team,
          name: 'Bot $team$i',
          spec: kCars[(team + i) % kCars.length],
          difficulty: level,
        ),
  ];
  return BoostBallMatch(teamSize: size, players: cars, random: Random(seed));
}

Future<void> _phone(
  WidgetTester tester, [
  Size size = const Size(375, 667),
]) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final save = BoostBallSave.instance
      ..coins = 0
      ..cars = {'zoomer'}
      ..car = 'zoomer'
      ..colour = 0
      ..wins = 0
      ..losses = 0
      ..goals = 0;
    await save.save();
  });

  test('cars and paint survive saving and loading', () async {
    final save = BoostBallSave.instance
      ..coins = 123
      ..cars = {'zoomer', 'monster'}
      ..car = 'monster'
      ..colour = 3;
    await save.save();
    save
      ..coins = 0
      ..cars = {}
      ..car = 'zoomer';
    await save.load();
    expect(save.coins, 123);
    expect(save.car, 'monster');
    expect(save.cars, containsAll(['zoomer', 'monster']));
    expect(save.colour, 3);
  });

  testWidgets('you can buy a car in the garage', (tester) async {
    await _phone(tester);
    BoostBallSave.instance.coins = 400;
    await BoostBallSave.instance.save();
    await tester.pumpWidget(const MaterialApp(home: BoostBallScreen()));
    await tester.pumpAndSettle();
    final buy = find.widgetWithText(ElevatedButton, '300');
    await tester.scrollUntilVisible(
      buy,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(buy);
    await tester.pumpAndSettle();
    await tester.tap(buy);
    await tester.pumpAndSettle();
    expect(BoostBallSave.instance.coins, 100);
    expect(BoostBallSave.instance.car, 'bulldog');
    expect(find.text('DRIVING'), findsOneWidget);
  });

  for (final size in [const Size(375, 667), const Size(740, 360)]) {
    testWidgets('a short match plays to the end on a $size screen', (
      tester,
    ) async {
      await _phone(tester, size);
      await tester.pumpWidget(
        const MaterialApp(home: BoostBallGameScreen(teamSize: 2, length: 8)),
      );
      expect(find.text('BOOST'), findsOneWidget);
      expect(find.text('JUMP'), findsOneWidget);
      // Drive and jump about a bit.
      final stick = await tester.startGesture(const Offset(60, 300));
      await stick.moveBy(const Offset(0, -40));
      for (var i = 0; i < 400; i++) {
        if (i == 80) await tester.tap(find.text('JUMP'));
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('PLAY AGAIN').evaluate().isNotEmpty) break;
      }
      await stick.up();
      // A draw goes to overtime, so keep going until someone scores.
      for (var i = 0; i < 6000; i++) {
        if (find.text('PLAY AGAIN').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final size in [1, 2, 3]) {
    test('bots score goals in a ${size}v$size game', () {
      final m = _botMatch(size, 1, size);
      var steps = 0;
      while (m.phase != MatchPhase.over && steps < 60 * 400) {
        m.step(1 / 60);
        steps++;
        expect(m.ball.x, inInclusiveRange(-1, kFieldW + 1));
        expect(
          m.ball.y,
          inInclusiveRange(-kGoalDepth - 1, kFieldL + kGoalDepth + 1),
        );
        expect(m.ball.z, inInclusiveRange(0, kCeiling));
        for (final c in m.cars) {
          expect(c.x, inInclusiveRange(-1, kFieldW + 1));
          expect(
            c.y,
            inInclusiveRange(-kGoalDepth - 1, kFieldL + kGoalDepth + 1),
          );
        }
      }
      // ignore: avoid_print
      print(
        '${size}v$size: ${m.score} in ${steps / 60}s overtime=${m.overtime}',
      );
      expect(m.score[0] + m.score[1], greaterThan(0));
    });
  }

  test('hard bots beat easy bots', () {
    var hard = 0, easy = 0;
    for (var seed = 0; seed < 4; seed++) {
      final cars = [
        Car(team: 0, name: 'Hard', spec: kCars.first, difficulty: 2),
        Car(team: 1, name: 'Easy', spec: kCars.first, difficulty: 0),
      ];
      final m = BoostBallMatch(
        teamSize: 1,
        players: cars,
        random: Random(seed),
      );
      for (var i = 0; i < 60 * 150 && m.phase != MatchPhase.over; i++) {
        m.step(1 / 60);
      }
      hard += m.score[0];
      easy += m.score[1];
    }
    // ignore: avoid_print
    print('hard $hard - easy $easy');
    expect(hard, greaterThan(easy));
  });
}
