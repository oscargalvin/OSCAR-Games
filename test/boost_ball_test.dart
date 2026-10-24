import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/boost_ball/boost_ball_data.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_game.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_net.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_screen.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_sim.dart';
import 'package:oscar_games/games/outplay/outplay_net.dart';

BoostBallMatch _botMatch(
  int size,
  int level,
  int seed, {
  BoostMode mode = BoostMode.classic,
}) {
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
  return BoostBallMatch(
    teamSize: size,
    players: cars,
    random: Random(seed),
    mode: mode,
  );
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

  test('a ball rolled at the side wall rides up it and comes back', () {
    final m = _botMatch(1, 1, 3);
    m.cars.clear();
    m.phase = MatchPhase.play;
    m.ball
      ..x = kFieldW / 2
      ..y = kFieldL / 2
      ..z = kBallR
      ..vx = 40
      ..vy = 0
      ..vz = 0;
    var highest = 0.0;
    for (var i = 0; i < 60 * 3; i++) {
      m.step(1 / 60);
      highest = max(highest, m.ball.z);
    }
    expect(highest, greaterThan(kRampR));
    expect(m.ball.x, lessThan(kFieldW - 3)); // it rolled back down
  });

  test('a car can drive up the curved wall', () {
    final car = Car(team: 0, name: 'You', spec: kCars.first, isYou: true);
    final m = BoostBallMatch(teamSize: 1, players: [car], random: Random(1));
    m.phase = MatchPhase.play;
    car
      ..x = 20
      ..y = 30
      ..heading = pi;
    car.input
      ..relative = true
      ..throttle = 1
      ..boost = true;
    var highest = 0.0;
    var tilted = false;
    for (var i = 0; i < 60 * 3; i++) {
      m.step(1 / 60);
      highest = max(highest, car.z);
      if (car.grounded && car.upZ < 0.8) tilted = true;
    }
    expect(highest, greaterThan(2));
    expect(tilted, isTrue);
  });

  test('steering right turns the car right', () {
    final car = Car(team: 0, name: 'You', spec: kCars.first, isYou: true);
    final m = BoostBallMatch(teamSize: 1, players: [car], random: Random(1));
    m.phase = MatchPhase.play;
    car
      ..x = 32
      ..y = 20
      ..heading = pi / 2; // facing up the pitch
    car.input
      ..relative = true
      ..throttle = 1
      ..steer = 1;
    for (var i = 0; i < 20; i++) {
      m.step(1 / 60);
    }
    expect(car.x, greaterThan(32)); // went right
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

  test('sudden death ends on the first goal', () {
    final m = _botMatch(1, 2, 5, mode: BoostMode.suddenDeath);
    var steps = 0;
    while (m.phase != MatchPhase.over && steps < 60 * 600) {
      m.step(1 / 60);
      steps++;
    }
    expect(m.phase, MatchPhase.over);
    expect(m.score[0] + m.score[1], 1);
  });

  test('first to 5 ends when a team gets 5 goals', () {
    final m = _botMatch(1, 2, 6, mode: BoostMode.firstTo5);
    var steps = 0;
    while (m.phase != MatchPhase.over && steps < 60 * 3000) {
      m.step(1 / 60);
      steps++;
    }
    expect(m.phase, MatchPhase.over);
    expect(max(m.score[0], m.score[1]), 5);
  });

  test('no boost mode has no pads and no boost', () {
    final m = _botMatch(2, 1, 7, mode: BoostMode.noBoost);
    expect(m.pads, isEmpty);
    for (var i = 0; i < 60 * 20; i++) {
      m.step(1 / 60);
      for (final c in m.cars) {
        expect(c.boost, 0);
      }
    }
  });

  test('hitting the ball shows how fast it went in KPH', () {
    final m = _botMatch(1, 1, 8);
    m.cars.removeLast();
    m.phase = MatchPhase.play;
    final c = m.cars.first
      ..x = kFieldW / 2
      ..y = kFieldL / 2 - 6
      ..heading = pi / 2
      ..vx = 0
      ..vy = 30;
    c.input.relative = true;
    for (var i = 0; i < 30 && m.lastKph == 0; i++) {
      m.step(1 / 60);
    }
    expect(m.lastKph, greaterThan(40));
    expect(m.kphT, greaterThan(0));
    expect(c.topKph, m.lastKph);
  });

  test('two people play each other online', () async {
    final hub = LoopbackHub();
    final hostRoom = await OutplayRoom.host(
      hub.makeLink,
      boostRoomMap(BoostMode.classic),
      teamSize: 1,
    );
    final host = BoostBallSession(
      room: hostRoom,
      lister: hub.makeDirectory(),
      myName: 'Oscar',
      myCar: kCars.first,
      myColour: 2,
      random: Random(1),
    );
    final guestRoom = await OutplayRoom.join(hub.makeLink, hostRoom.code);
    final guest = BoostBallSession(
      room: guestRoom,
      myName: 'Friend',
      myCar: kCars[1],
      myColour: 4,
      random: Random(2),
    );
    expect(guest.mode, BoostMode.classic);
    for (var i = 0; i < 10 && !(host.started && guest.started); i++) {
      host.update(1 / 30);
      guest.update(1 / 30);
    }
    expect(host.started, isTrue);
    expect(guest.started, isTrue);
    final h = host.match!, g = guest.match!;
    expect(h.cars.length, 2);
    expect(g.cars.length, 2);
    // Each phone drives its own car; the other one is the real person.
    expect(host.you!.team, 0);
    expect(guest.you!.team, 1);
    expect(g.cars[0].name, 'Oscar');
    expect(h.cars[1].name, 'Friend');
    expect(h.cars[1].human, isTrue);
    // The friend drives forward: their car moves on the room maker's phone.
    final startY = h.cars[1].y;
    guest.you!.input.throttle = 1;
    for (var i = 0; i < 30 * 7; i++) {
      guest.you!.input.throttle = 1;
      host.update(1 / 30);
      guest.update(1 / 30);
    }
    expect(h.phase, MatchPhase.play);
    expect((h.cars[1].y - startY).abs(), greaterThan(10));
    // Both phones agree where the ball and cars are.
    expect((g.ball.x - h.ball.x).abs(), lessThan(3));
    expect((g.ball.y - h.ball.y).abs(), lessThan(3));
    expect((g.cars[0].y - h.cars[0].y).abs(), lessThan(3));
    expect(g.clock, closeTo(h.clock, 0.5));
    // The friend leaves: a bot takes over their car.
    guest.close();
    host.update(1 / 30);
    expect(h.cars[1].netControlled, isFalse);
    host.close();
  });

  test('the room maker can start early with bots', () async {
    final hub = LoopbackHub();
    final room = await OutplayRoom.host(
      hub.makeLink,
      boostRoomMap(BoostMode.firstTo5),
      teamSize: 2,
    );
    final host = BoostBallSession(
      room: room,
      myName: 'Oscar',
      myCar: kCars.first,
      myColour: 0,
    );
    host.update(0.1);
    expect(host.started, isFalse);
    expect(host.waiting, ['Oscar']);
    host.startNow();
    expect(host.match!.cars.length, 4);
    expect(host.match!.mode, BoostMode.firstTo5);
    expect(host.match!.cars.where((c) => c.netControlled), isEmpty);
    host.close();
  });

  testWidgets('the garage shows game modes and online play', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(const MaterialApp(home: BoostBallScreen()));
    await tester.pumpAndSettle();
    for (final m in BoostMode.values) {
      expect(find.text(m.title), findsOneWidget);
    }
    await tester.ensureVisible(find.text('PEOPLE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PEOPLE'));
    await tester.pumpAndSettle();
    expect(find.text('FIND PLAYERS 1v1'), findsOneWidget);
    expect(find.text('MAKE A ROOM'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Free Play'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free Play'));
    await tester.pumpAndSettle();
    expect(find.text('START FREE PLAY'), findsOneWidget);
  });

  testWidgets('free play is just you and the ball', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: BoostBallGameScreen(mode: BoostMode.freePlay)),
    );
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('FREE PLAY'), findsOneWidget);
    expect(find.text('100'), findsOneWidget); // boost never runs out
    await tester.pumpWidget(const SizedBox());
  });

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
