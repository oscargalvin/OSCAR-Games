import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/zombie_attack/zombie_3d.dart';
import 'package:oscar_games/games/zombie_attack/zombie_data.dart';
import 'package:oscar_games/games/zombie_attack/zombie_game.dart';
import 'package:oscar_games/games/zombie_attack/zombie_screen.dart';
import 'package:oscar_games/games/zombie_attack/zombie_sim.dart';

/// Runs the world for [seconds] with whatever the input is.
void _run(ZombieWorld w, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    w.step(1 / 60);
    if (w.phase == ZombiePhase.over) return;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ZombieSave.instance
      ..coins = 0
      ..guns = {'pistol'}
      ..gun = 'pistol'
      ..bestWave = 0
      ..kills = 0;
  });

  test('every map leaves the middle clear and blocks inside the world', () {
    for (final m in ZombieMap.values) {
      final w = ZombieWorld(map: m, random: Random(1));
      expect(w.blocks, isNotEmpty);
      for (final b in w.blocks) {
        expect(b.contains(w.player), isFalse, reason: '${m.name} $b');
        expect(b.left >= 0 && b.right <= kWorldW, isTrue);
        expect(b.top >= 0 && b.bottom <= kWorldH, isTrue);
        for (final zone in kSafeZones) {
          expect(
            zone.overlaps(b),
            isFalse,
            reason: '${m.name} $b in a safe zone',
          );
        }
      }
    }
  });

  test('waves start, zombies come for you and bite', () {
    final w = ZombieWorld(random: Random(2));
    _run(w, 3);
    expect(w.wave, 1);
    expect(w.phase, ZombiePhase.play);
    expect(w.zombiesLeft, 6);
    // Standing still and not shooting: the zombies catch you.
    _run(w, 40);
    expect(w.hp, lessThan(kMaxHp));
  });

  test('auto aim clears waves and earns coins', () {
    final w = ZombieWorld(level: 0, random: Random(3))..input.autoAim = true;
    _run(w, 60);
    expect(w.kills, greaterThan(5));
    expect(w.wavesCleared, greaterThanOrEqualTo(1));
    expect(w.coinsEarned, greaterThanOrEqualTo(kWaveCoins[0]));
  });

  test('doing nothing on hard ends the game', () {
    final w = ZombieWorld(level: 2, random: Random(4));
    _run(w, 200);
    expect(w.phase, ZombiePhase.over);
    expect(w.hp, 0);
  });

  test('a grenade blows up a crowd', () {
    final w = ZombieWorld(random: Random(5));
    _run(w, 3); // wave 1 starts
    w.zombies.clear();
    for (var i = 0; i < 4; i++) {
      w.zombies.add(
        Zombie(
          100 + i,
          ZombieKind.walker,
          w.player + Offset(-0.5 + i * 0.3, -kGrenadeRange),
          1,
          0,
        ),
      );
    }
    w.aimAngle = -pi / 2;
    w.input.grenade = true;
    final before = w.grenades;
    _run(w, 1.2);
    expect(w.grenades, before - 1);
    expect(w.kills, greaterThanOrEqualTo(3));
  });

  test('the rocket launcher splashes nearby zombies', () {
    final w = ZombieWorld(gun: gunById('rocket'), random: Random(6));
    _run(w, 3);
    w.zombies.clear();
    for (var i = 0; i < 3; i++) {
      w.zombies.add(
        Zombie(
          200 + i,
          ZombieKind.walker,
          w.player + Offset(-1 + i.toDouble(), -8),
          1,
          0,
        ),
      );
    }
    w.input.aim = const Offset(0, -1);
    w.input.fire = true;
    _run(w, 0.6);
    expect(w.kills, 3);
  });

  test('zombies cannot get into a safe zone or bite you there', () {
    final w = ZombieWorld(random: Random(7));
    w.player = const Offset(3, 3); // top-left corner
    _run(w, 3);
    w.zombies
      ..clear()
      ..add(Zombie(1, ZombieKind.walker, const Offset(12, 4), 1, 0));
    _run(w, 8);
    expect(w.hp, kMaxHp);
    final z = w.zombies.firstWhere((z) => z.id == 1);
    expect(kSafeZones.first.inflate(z.r - 0.01).contains(z.pos), isFalse);
    // Step out and it bites.
    w.player = Offset(kSafeSize + 1.5, 3);
    _run(w, 3);
    expect(w.hp, lessThan(kMaxHp));
  });

  test('sword zombies drop a sword you can pick up and swing', () {
    final w = ZombieWorld(random: Random(8));
    _run(w, 3);
    w.zombies
      ..clear()
      ..add(
        Zombie(1, ZombieKind.walker, w.player + const Offset(0, -8), 1, 0)
          ..sword = true,
      );
    w.input
      ..aim = const Offset(0, -1)
      ..fire = true;
    _run(w, 1.5);
    w.input.fire = false;
    expect(w.kills, 1);
    final drop = w.pickups.singleWhere((p) => p.kind == PickupKind.sword);
    w.player = drop.pos;
    _run(w, 0.1);
    expect(w.weapons.map((g) => g.id), ['pistol', 'sword']);
    expect(w.gun.melee, isTrue);

    // A swing hits zombies right in front of you.
    w.zombies.add(
      Zombie(2, ZombieKind.walker, w.player + const Offset(0, -2), 1, 0),
    );
    w.aimAngle = -pi / 2;
    w.input
      ..aim = const Offset(0, -1)
      ..fire = true;
    _run(w, 0.5);
    expect(w.kills, 2);
    expect(w.bullets, isEmpty);

    // Swap back to the pistol.
    w.input
      ..fire = false
      ..swap = true;
    _run(w, 0.1);
    expect(w.gun.id, 'pistol');
  });

  test('sword drops are only sometimes yours to keep', () {
    var kept = 0;
    for (var seed = 0; seed < 400; seed++) {
      final w = ZombieWorld(random: Random(seed));
      w.pickups.add(Pickup(PickupKind.sword, w.player));
      w.step(1 / 60);
      expect(w.events, contains(ZombieEvent.newWeapon));
      if (w.keptSword) kept++;
    }
    expect(kept, inInclusiveRange(4, 45)); // about 5%
  });

  test('sword zombies show up from wave 2', () {
    final w = ZombieWorld(level: 0, random: Random(9))..input.autoAim = true;
    var seen = false;
    for (var t = 0.0; t < 120 && !seen; t += 1 / 60) {
      w.step(1 / 60);
      seen = w.zombies.any((z) => z.sword);
      if (w.phase == ZombiePhase.over) break;
    }
    expect(seen, isTrue);
  });

  testWidgets('menu buys a gun with coins and starts a game', (tester) async {
    tester.view.physicalSize = const Size(375, 667) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    ZombieSave.instance.coins = 350;

    await tester.pumpWidget(const MaterialApp(home: ZombieScreen()));
    await tester.pumpAndSettle();
    expect(find.text('350'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Shotgun'), 200);
    await tester.tap(find.text('Shotgun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BUY'));
    await tester.pumpAndSettle();
    expect(ZombieSave.instance.coins, 50);
    expect(ZombieSave.instance.gun, 'shotgun');
    expect(find.text('USING'), findsOneWidget);

    // Too expensive: nothing is bought.
    await tester.scrollUntilVisible(find.text('Rocket Launcher'), 200);
    await tester.tap(find.text('Rocket Launcher'));
    await tester.pumpAndSettle();
    expect(find.text('BUY'), findsNothing);
    expect(ZombieSave.instance.guns, isNot(contains('rocket')));

    await tester.scrollUntilVisible(find.text('PLAY'), -200);
    await tester.ensureVisible(find.text('PLAY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PLAY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ZombieGameScreen), findsOneWidget);
    expect(find.text('WAVE 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('losing pays your coins and shows the end card', (tester) async {
    tester.view.physicalSize = const Size(844, 390) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: ZombieGameScreen(level: 2)),
    );
    // Stand still until the zombies win.
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('THE ZOMBIES GOT YOU!').evaluate().isNotEmpty) break;
    }
    expect(find.text('THE ZOMBIES GOT YOU!'), findsOneWidget);
    expect(find.text('PLAY AGAIN'), findsOneWidget);

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(find.text('THE ZOMBIES GOT YOU!'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('3D view: drag to turn, hold SHOOT to shoot', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ZombieGameScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    final w = _world(tester);
    final before = w.aimAngle;

    // Drag on the right half to turn the camera (and your gun).
    final g = await tester.startGesture(const Offset(300, 450));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(w.aimAngle, isNot(closeTo(before, 0.3)));

    // Nothing shoots until you press the button.
    await tester.pump(const Duration(milliseconds: 500));
    expect(w.bullets, isEmpty);
    final shoot = await tester.startGesture(
      tester.getCenter(find.text('SHOOT')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(w.bullets, isNotEmpty);
    await shoot.up();
    await tester.pumpWidget(const SizedBox());
  });
}

ZombieWorld _world(WidgetTester tester) {
  final painter = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<Zombie3dPainter>()
      .first;
  return painter.w;
}
