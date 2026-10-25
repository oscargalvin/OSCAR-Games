import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/zombie_attack/zombie_3d.dart';
import 'package:oscar_games/games/zombie_attack/zombie_data.dart';
import 'package:oscar_games/games/outplay/outplay_net.dart';
import 'package:oscar_games/games/zombie_attack/zombie_game.dart';
import 'package:oscar_games/games/zombie_attack/zombie_net.dart';
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
    // You can't shoot or throw grenades from in there.
    w.input
      ..aim = const Offset(1, 0)
      ..fire = true
      ..grenade = true;
    _run(w, 1);
    expect(w.bullets, isEmpty);
    expect(w.thrown, isEmpty);
    expect(w.grenades, 2);
    w.input.fire = false;
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

  test('room names round-trip', () {
    const setup = ZombieRoomSetup(
      ZombieMode.versus,
      ZombieMap.snow,
      2,
      hostIsZombie: true,
    );
    final back = ZombieRoomSetup.parse(setup.roomName)!;
    expect(back.mode, ZombieMode.versus);
    expect(back.map, ZombieMap.snow);
    expect(back.level, 2);
    expect(back.hostIsZombie, isTrue);
    expect(back.zombieHere(true), isTrue);
    expect(back.zombieHere(false), isFalse);
    expect(back.players, 2);
    expect(ZombieRoomSetup.parse('bb:classic'), isNull);
    // Older room names without a player count are for 2.
    expect(ZombieRoomSetup.parse('za:coop:town:1:h')!.players, 2);
    final four = ZombieRoomSetup.parse(
      const ZombieRoomSetup(
        ZombieMode.coop,
        ZombieMap.farm,
        1,
        players: 4,
      ).roomName,
    )!;
    expect(four.players, 4);
    expect(four.roomTeamSize, 2);
  });

  test('four people team up online', () async {
    final s = await _group(
      const ZombieRoomSetup(ZombieMode.coop, ZombieMap.farm, 1, players: 4),
      4,
    );
    final h = s.first.world!;
    expect(h.survivors.map((x) => x.name), [
      'Oscar',
      'Friend 1',
      'Friend 2',
      'Friend 3',
    ]);
    for (var i = 0; i < 4; i++) {
      expect(s[i].world!.youIndex, i);
      expect(s[i].world!.survivors.length, 4);
    }
    // The third friend walks: it shows on the room maker's phone and on
    // the first friend's phone.
    final start = h.survivors[3].pos;
    for (var t = 0.0; t < 1; t += 1 / 30) {
      s[3].world!.input.move = const Offset(1, 0);
      for (final x in s) {
        x.update(1 / 30);
      }
    }
    expect(h.survivors[3].pos.dx, greaterThan(start.dx + 4));
    expect(
      s[1].world!.survivors[3].pos.dx,
      closeTo(h.survivors[3].pos.dx, 1.5),
    );
    // Way more zombies for four.
    _all(s, 4);
    expect(h.wave, 1);
    expect(h.zombiesLeft, greaterThan(12));

    // Someone leaves: they're out for good, the others play on.
    s[2].close();
    _all([s[0], s[1], s[3]], 0.5);
    expect(h.survivors[2].gone, isTrue);
    expect(h.survivors[2].alive, isFalse);
    expect(h.phase, isNot(ZombiePhase.over));
  });

  test('three players: one is the zombies, two are humans', () async {
    final s = await _group(
      const ZombieRoomSetup(ZombieMode.versus, ZombieMap.town, 1, players: 3),
      3,
    );
    final h = s.first.world!;
    expect(h.survivors.map((x) => x.name), ['Oscar', 'Friend 2']);
    expect(h.boss!.name, 'Friend 1');
    expect(s[1].youAreZombie, isTrue);
    expect(s[1].world!.youAreBoss, isTrue);
    expect(s[2].world!.youIndex, 1);
    // The zombie player sends a zombie in from their phone.
    _all(s, 3);
    h.boss!.brains = 5;
    final before = h.boss!.brains;
    s[1].order(ZombieOrder.walker);
    _all(s, 0.1);
    expect(h.boss!.brains, lessThan(before));
  });

  test('a full game turns away anyone extra', () async {
    final s = await _group(
      const ZombieRoomSetup(ZombieMode.coop, ZombieMap.town, 1, players: 3),
      3,
    );
    final hub = _lastHub!;
    final late = ZombieSession(
      room: await OutplayRoom.join(hub.makeLink, s.first.room.code),
      myName: 'Late',
    );
    for (var i = 0; i < 10; i++) {
      s.first.update(1 / 30);
      late.update(1 / 30);
    }
    expect(late.started, isFalse);
    expect(late.ended, 'That game is already full.');
    expect(s.first.world!.survivors.length, 3);
  });

  test('two people team up against the zombies online', () async {
    final (host, guest) = await _pair(
      const ZombieRoomSetup(ZombieMode.coop, ZombieMap.town, 1),
    );
    final h = host.world!, g = guest.world!;
    expect(h.survivors.map((s) => s.name), ['Oscar', 'Friend']);
    expect(g.survivors.map((s) => s.name), ['Oscar', 'Friend']);
    expect(h.youIndex, 0);
    expect(g.youIndex, 1);
    expect(h.survivors[0].gun.id, 'shotgun');
    expect(g.authority, isFalse);

    // The friend walks right: they move on the room maker's phone too.
    final start = h.survivors[1].pos;
    for (var t = 0.0; t < 1; t += 1 / 30) {
      g.input.move = const Offset(1, 0);
      host.update(1 / 30);
      guest.update(1 / 30);
    }
    expect(h.survivors[1].pos.dx, greaterThan(start.dx + 4));

    // Waves come for both and show up on the friend's phone.
    _both(host, guest, 4);
    expect(h.wave, 1);
    expect(g.wave, 1);
    expect(g.zombies.length, h.zombies.length);
    expect(h.zombiesLeft, greaterThan(6)); // more zombies for two

    // The friend's grenade is thrown by the room maker's phone.
    guest.grenade();
    _both(host, guest, 0.2);
    expect(h.survivors[1].grenades, 1);
    expect(g.survivors[1].grenades, 1);
  });

  test('zombie vs human: send zombies, then become the King', () async {
    final (host, guest) = await _pair(
      const ZombieRoomSetup(
        ZombieMode.versus,
        ZombieMap.town,
        0,
        hostIsZombie: true,
      ),
    );
    final h = host.world!, g = guest.world!;
    expect(host.youAreZombie, isTrue);
    expect(guest.youAreZombie, isFalse);
    expect(h.youAreBoss, isTrue);
    expect(g.youAreBoss, isFalse);
    expect(h.survivors.single.name, 'Friend');
    expect(h.boss!.name, 'Oscar');

    // The zombie player sends a runner in once they have the brains.
    _both(host, guest, 3);
    final before = h.zombies.length;
    h.boss!.pos = const Offset(10, 32);
    h.boss!.brains = 5;
    host.order(ZombieOrder.runner);
    _both(host, guest, 0.1);
    expect(h.zombies.length, greaterThan(before));
    expect(h.boss!.brains, lessThan(4));

    // Skip ahead to wave 4: the King arrives and the zombie player drives it.
    h.wave = kKingArrives - 1;
    h.zombies.clear();
    for (var t = 0.0; t < 60 && h.king == null; t += 1 / 30) {
      h.zombies.removeWhere((z) => !z.controlled);
      host.update(1 / 30);
      guest.update(1 / 30);
    }
    final king = h.king!;
    expect(king.controlled, isTrue);
    _both(host, guest, 0.2);
    expect(g.king, isNotNull);
    final kingStart = king.pos;
    h.boss!.input.move = const Offset(1, 0);
    _both(host, guest, 0.5);
    expect(king.pos.dx, greaterThan(kingStart.dx + 1));

    // The human beats the King: the humans win on both phones.
    king.hp = 0.5;
    h.survivors.single.pos = king.pos + const Offset(0, 6);
    h.survivors.single.aimAngle = -pi / 2;
    for (var t = 0.0; t < 3 && h.phase != ZombiePhase.over; t += 1 / 30) {
      g.input
        ..aim = king.pos - h.survivors.single.pos
        ..fire = true;
      host.update(1 / 30);
      guest.update(1 / 30);
    }
    _both(host, guest, 0.2);
    expect(h.winner, 'humans');
    expect(g.winner, 'humans');
    expect(g.phase, ZombiePhase.over);
  });

  test('the King smashes people, and wins if they all go down', () {
    final w = ZombieWorld(mode: ZombieMode.versus, random: Random(3))
      ..youIndex = -1;
    w.wave = kKingArrives - 1;
    w.phaseT = 0.01;
    w.step(1 / 60);
    final king = w.king!;
    final s = w.survivors.single;
    s.pos = king.pos + const Offset(2.5, 0);
    w.boss!.input
      ..aim = const Offset(1, 0)
      ..fire = true;
    for (var t = 0.0; t < 10 && w.phase != ZombiePhase.over; t += 1 / 60) {
      s.pos = king.pos + const Offset(2.5, 0);
      w.zombies.removeWhere((z) => !z.controlled);
      w.step(1 / 60);
    }
    expect(w.winner, 'zombies');
  });

  testWidgets('2-player screens: waiting room, then zombie buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final hub = LoopbackHub();
    const setup = ZombieRoomSetup(
      ZombieMode.versus,
      ZombieMap.town,
      1,
      hostIsZombie: true,
    );
    final room = (await tester.runAsync(
      () => OutplayRoom.host(
        hub.makeLink,
        setup.roomName,
        teamSize: 1,
        showCode: true,
      ),
    ))!;
    final host = ZombieSession(room: room, myName: 'Oscar');
    await tester.pumpWidget(MaterialApp(home: ZombieGameScreen(session: host)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(room.code), findsOneWidget);
    expect(find.text('You are the zombies!'), findsOneWidget);

    final guestRoom = (await tester.runAsync(
      () => OutplayRoom.join(hub.makeLink, room.code),
    ))!;
    final guest = ZombieSession(room: guestRoom, myName: 'Friend');
    for (var i = 0; i < 10 && !host.started; i++) {
      guest.update(1 / 30);
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(host.started, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Walker'), findsOneWidget);
    expect(find.text('Tank'), findsOneWidget);
    expect(find.text('SHOOT'), findsNothing);
    expect(find.text('The Zombie King comes at wave 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    guest.close();
  });

  test('jumping goes up, comes down, and dodges bites', () {
    final w = ZombieWorld(random: Random(12));
    w.input.jump = true;
    w.step(1 / 60);
    var top = 0.0;
    for (var i = 0; i < 30; i++) {
      w.step(1 / 60);
      top = max(top, w.you.jumpZ);
    }
    expect(top, greaterThan(1));
    for (var i = 0; i < 60; i++) {
      w.step(1 / 60);
    }
    expect(w.you.jumpZ, 0);
    // High in the air, a zombie right next to you can't bite.
    _run(w, 3);
    w.zombies
      ..clear()
      ..add(Zombie(1, ZombieKind.walker, w.player + const Offset(1, 0), 1, 0));
    w.you
      ..jumpZ = 1.2
      ..jumpV = 0.1;
    w.step(1 / 60);
    expect(w.hp, kMaxHp);
  });

  testWidgets('Space jumps', (tester) async {
    tester.view.physicalSize = const Size(844, 390) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ZombieGameScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    final w = _world(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    expect(w.you.jumpZ, greaterThan(0.3));
    expect(w.bullets, isEmpty);
    expect(find.text('JUMP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

LoopbackHub? _lastHub;

/// The room maker plus [n] - 1 friends, all in a started game.
Future<List<ZombieSession>> _group(ZombieRoomSetup setup, int n) async {
  final hub = _lastHub = LoopbackHub();
  final hostRoom = await OutplayRoom.host(
    hub.makeLink,
    setup.roomName,
    teamSize: setup.roomTeamSize,
    showCode: true,
  );
  final all = [
    ZombieSession(room: hostRoom, myName: 'Oscar', random: Random(1)),
  ];
  for (var i = 1; i < n; i++) {
    final room = await OutplayRoom.join(hub.makeLink, hostRoom.code);
    all.add(ZombieSession(room: room, myName: 'Friend $i'));
    // Let each one say hello before the next joins, so the order is known.
    for (var k = 0; k < 3; k++) {
      for (final x in all) {
        x.update(1 / 30);
      }
    }
  }
  for (var i = 0; i < 20 && !all.every((x) => x.started); i++) {
    for (final x in all) {
      x.update(1 / 30);
    }
  }
  for (final x in all) {
    expect(x.started, isTrue);
  }
  return all;
}

void _all(List<ZombieSession> s, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 30) {
    for (final x in s) {
      x.update(1 / 30);
    }
  }
}

Future<(ZombieSession, ZombieSession)> _pair(ZombieRoomSetup setup) async {
  final hub = LoopbackHub();
  final hostRoom = await OutplayRoom.host(
    hub.makeLink,
    setup.roomName,
    teamSize: setup.roomTeamSize,
    showCode: true,
  );
  final host = ZombieSession(
    room: hostRoom,
    myName: 'Oscar',
    myGun: 'shotgun',
    random: Random(1),
  );
  final guestRoom = await OutplayRoom.join(hub.makeLink, hostRoom.code);
  final guest = ZombieSession(room: guestRoom, myName: 'Friend');
  for (var i = 0; i < 20 && !(host.started && guest.started); i++) {
    host.update(1 / 30);
    guest.update(1 / 30);
  }
  expect(host.started, isTrue);
  expect(guest.started, isTrue);
  return (host, guest);
}

void _both(ZombieSession a, ZombieSession b, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 30) {
    a.update(1 / 30);
    b.update(1 / 30);
  }
}

ZombieWorld _world(WidgetTester tester) {
  final painter = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<Zombie3dPainter>()
      .first;
  return painter.w;
}
