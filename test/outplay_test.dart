import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/outplay/outplay_avatar.dart';
import 'package:oscar_games/games/outplay/outplay_data.dart';
import 'package:oscar_games/games/outplay/outplay_game.dart';
import 'package:oscar_games/games/outplay/outplay_maps.dart';
import 'package:oscar_games/games/outplay/outplay_net.dart';
import 'package:oscar_games/games/outplay/outplay_screen.dart';

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375, 667) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OutplaySave.instance.load();
  });

  testWidgets('walking with the joystick reaches the Quick Play pad', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(const MaterialApp(home: OutplayGameScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Quick Play'), findsNothing);

    // The Quick Play pad is ahead and to the left: push the stick that way.
    final stick = await tester.startGesture(const Offset(80, 560));
    await stick.moveBy(const Offset(-10, -20));
    await stick.moveBy(const Offset(-14.6, -29.2));
    for (
      var i = 0;
      i < 120 && find.text('Quick Play').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    await stick.up();
    expect(find.text('Quick Play'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a big free-for-all plays all the way to the end', (
    tester,
  ) async {
    await _phone(tester);
    final coinsBefore = OutplaySave.instance.coins;
    await tester.pumpWidget(
      const MaterialApp(
        home: OutplayGameScreen(
          mode: OutplayMode.freeForAll,
          mapId: 'warehouse',
          bots: 7,
        ),
      ),
    );
    var finished = false;
    for (var i = 0; i < 200 * 20 && !finished; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      finished =
          find.text('VICTORY').evaluate().isNotEmpty ||
          find.text('DEFEAT').evaluate().isNotEmpty;
    }
    expect(finished, isTrue);
    // Coins only come from winning; standing still you usually lose.
    if (find.text('VICTORY').evaluate().isNotEmpty) {
      expect(OutplaySave.instance.coins, greaterThan(coinsBefore));
    } else {
      expect(OutplaySave.instance.coins, coinsBefore);
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final map in [
    'volcano',
    'runway',
    'courtyard',
    'mansion',
    'crocs',
    'arena',
    'lake',
    'goat_karts',
  ]) {
    testWidgets('the bot wins rounds on $map', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: OutplayGameScreen(mode: OutplayMode.duel, mapId: map),
        ),
      );
      // Stand still: the bot (or the lava, or a car) should get you.
      var scored = false;
      for (var i = 0; i < 240 * 20 && !scored; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        scored =
            find.textContaining('You 0 - 1').evaluate().isNotEmpty ||
            find.text('You got outplayed').evaluate().isNotEmpty;
      }
      expect(scored, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('two players meet in an online room and fight', (tester) async {
    tester.view.physicalSize = const Size(750, 667) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final hub = LoopbackHub();
    final hostRoom = await OutplayRoom.host(hub.makeLink, 'warehouse');
    final guestRoom = await OutplayRoom.join(hub.makeLink, hostRoom.code);
    expect(guestRoom.mapId, 'warehouse');
    final guestKey = GlobalKey();

    Widget app({required bool withHost}) => MaterialApp(
      home: Row(
        children: [
          if (withHost)
            Expanded(
              child: OutplayGameScreen(
                mode: OutplayMode.online,
                mapId: hostRoom.mapId,
                room: hostRoom,
                makeDirectory: hub.makeDirectory,
              ),
            ),
          Expanded(
            child: OutplayGameScreen(
              key: guestKey,
              mode: OutplayMode.online,
              mapId: guestRoom.mapId,
              room: guestRoom,
            ),
          ),
        ],
      ),
    );

    // Someone looking at the Join list.
    var listed = <RoomInfo>[];
    hub.makeDirectory().browse((rooms) => listed = rooms);

    await tester.pumpWidget(app(withHost: true));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Both phones see each other in the waiting room.
    expect(find.text('Players here'), findsNWidgets(2));
    // The room shows up on the Join list.
    expect(listed.single.code, hostRoom.code);
    expect(listed.single.players, 2);
    expect(listed.single.playing, isFalse);
    await tester.tap(find.text('START'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('KOs 0'), findsNWidgets(2));

    // The guest's phone says it hit the host hard enough to knock them out.
    guestRoom.send({
      't': 'hit',
      'to': hostRoom.myId,
      'by': guestRoom.myId,
      'dmg': 500,
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.textContaining(RegExp(r'^Player \d+ outplayed you$')),
      findsOneWidget,
    );
    expect(find.textContaining('KOs 1'), findsOneWidget);

    // The host leaves: the guest is told the room closed.
    await tester.pumpWidget(app(withHost: false));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('The player who made the room left.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('a 1v1 room lets in one person and turns the next away', () async {
    final hub = LoopbackHub();
    final host = await OutplayRoom.host(hub.makeLink, 'crocs', teamSize: 1);
    final first = await OutplayRoom.join(hub.makeLink, host.code);
    expect(first.teamSize, 1);
    expect(first.myTeam, 1);
    expect(first.mapId, 'crocs');
    expect(
      () => OutplayRoom.join(hub.makeLink, host.code),
      throwsA(contains('full')),
    );
  });

  test('a 2v2 room shares people out between the teams', () async {
    final hub = LoopbackHub();
    final host = await OutplayRoom.host(hub.makeLink, 'arena', teamSize: 2);
    final teams = [host.myTeam];
    for (var i = 0; i < 3; i++) {
      teams.add((await OutplayRoom.join(hub.makeLink, host.code)).myTeam);
    }
    expect(teams.where((t) => t == 0).length, 2);
    expect(teams.where((t) => t == 1).length, 2);
    expect(
      () => OutplayRoom.join(hub.makeLink, host.code),
      throwsA(contains('full')),
    );
  });

  testWidgets('a 3v3 against AI plays to the end', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: OutplayGameScreen(
          mode: OutplayMode.teams,
          teamSize: 3,
          mapId: 'arena',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Your team 0 - 0 Them'), findsOneWidget);
    var finished = false;
    for (var i = 0; i < 200 * 20 && !finished; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      finished =
          find.text('VICTORY').evaluate().isNotEmpty ||
          find.text('DEFEAT').evaluate().isNotEmpty;
    }
    expect(finished, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pressing AI asks easy, medium or hard', (tester) async {
    await _phone(tester);
    OutplaySave.instance.name = 'Oscar';
    await tester.pumpWidget(const MaterialApp(home: OutplayGameScreen()));
    final stick = await tester.startGesture(const Offset(80, 560));
    await stick.moveBy(const Offset(-10, -20));
    await stick.moveBy(const Offset(-14.6, -29.2));
    for (var i = 0; i < 120 && find.text('1v1').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    await stick.up();
    await tester.tap(find.text('1v1'));
    await tester.pump();
    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(find.text('EASY'), findsOneWidget);
    expect(find.text('MEDIUM'), findsOneWidget);
    expect(find.text('HARD'), findsOneWidget);
    await tester.tap(find.text('HARD'));
    await tester.pump();
    expect(find.text('Quick Play 1v1 · AI · Hard'), findsOneWidget);
    await tester.tap(find.text('PLAY'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final game = tester.widget<OutplayGameScreen>(
      find.byType(OutplayGameScreen).last,
    );
    expect(game.difficulty, 2);
    await tester.pumpWidget(const SizedBox());
  });

  for (final level in [0, 2]) {
    testWidgets('a game against ${level == 0 ? 'easy' : 'hard'} AI '
        'gets going', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: OutplayGameScreen(mode: OutplayMode.duel, difficulty: level),
        ),
      );
      var scored = false;
      for (var i = 0; i < 240 * 20 && !scored; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        scored = find.textContaining('You 0 - 1').evaluate().isNotEmpty;
      }
      expect(scored, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('quick play against a human waits in a 1v1 room', (tester) async {
    await _phone(tester);
    OutplaySave.instance.name = 'Oscar';
    final hub = LoopbackHub();
    var listed = <RoomInfo>[];
    hub.makeDirectory().browse((rooms) => listed = rooms);
    await tester.pumpWidget(
      MaterialApp(
        home: OutplayGameScreen(
          makeLink: hub.makeLink,
          makeDirectory: hub.makeDirectory,
        ),
      ),
    );
    // Walk to the Quick Play pad.
    final stick = await tester.startGesture(const Offset(80, 560));
    await stick.moveBy(const Offset(-10, -20));
    await stick.moveBy(const Offset(-14.6, -29.2));
    for (var i = 0; i < 120 && find.text('1v1').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    await stick.up();
    // Quick Play asks: how big, AI or human, which map.
    await tester.tap(find.text('1v1'));
    await tester.pump();
    await tester.tap(find.text('HUMAN'));
    await tester.pump();
    await tester.tap(find.text('Crazy Crocs'));
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Nobody else was looking, so we wait for someone in our own 1v1 room.
    expect(find.text('Finding players… 1/2'), findsOneWidget);
    // No room codes in Quick Play.
    expect(find.textContaining('room code'), findsNothing);
    expect(listed.single.teamSize, 1);
    expect(listed.single.mapId, 'crocs');
    expect(listed.single.name, 'Oscar');

    // Someone else presses Human and lands in our room: it starts.
    final other = await OutplayRoom.join(hub.makeLink, listed.single.code);
    for (var i = 0; i < 10; i++) {
      other.send({
        't': 's',
        'id': other.myId,
        'n': 'Friend',
        'x': 6.5,
        'y': 3.5,
        'tm': 1,
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Online 1v1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 2v2 code room shows its code and starts when 4 are in', (
    tester,
  ) async {
    await _phone(tester);
    OutplaySave.instance.name = 'Oscar';
    final hub = LoopbackHub();
    var listed = <RoomInfo>[];
    hub.makeDirectory().browse((rooms) => listed = rooms);
    final room = await OutplayRoom.host(
      hub.makeLink,
      'arena',
      teamSize: 2,
      showCode: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OutplayGameScreen(
          mode: OutplayMode.online,
          mapId: room.mapId,
          room: room,
          makeDirectory: hub.makeDirectory,
        ),
      ),
    );
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Waiting for players… 1/4'), findsOneWidget);
    expect(find.text(room.code), findsOneWidget);
    // Quick Play strangers leave friends' rooms alone.
    expect(listed.single.friends, isTrue);

    // Three friends type the code in and go straight into the room.
    final friends = [
      for (var i = 0; i < 3; i++)
        await OutplayRoom.join(hub.makeLink, room.code),
    ];
    expect(friends.every((f) => f.showCode && f.teamSize == 2), isTrue);
    for (var i = 0; i < 10; i++) {
      for (final (n, f) in friends.indexed) {
        f.send({
          't': 's',
          'id': f.myId,
          'n': 'Friend $n',
          'x': 6.5,
          'y': 3.5 + n,
          'tm': f.myTeam,
        });
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Online 2v2'), findsOneWidget);
    // A fifth person is turned away.
    expect(
      () => OutplayRoom.join(hub.makeLink, room.code),
      throwsA(contains('already full')),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('Lazy Lake has water in the middle and dry places to start', () {
    final lake = mapById('lake');
    expect(lake.isWater(lake.centre), isTrue);
    for (final s in lake.spawnPoints()) {
      expect(lake.isWater(s), isFalse, reason: '$s');
    }
  });

  test('the goat karts stay on the race track', () {
    final track = mapById('goat_karts');
    for (var s = 0.0; s < track.loopLength; s += 0.25) {
      final p = track.loopPoint(s);
      expect(track.trackOffset(p).abs(), lessThan(0.01), reason: '$s');
      for (final lane in [-0.7, 0.7]) {
        final q = p + Offset(lane, 0);
        expect(track.solidAt(q.dx.floor(), q.dy.floor()), isFalse);
      }
    }
    for (final s in track.spawnPoints()) {
      expect(track.onTrack(s), isFalse, reason: '$s');
    }
  });

  test('the Sizzler hooks people and is the second best melee', () {
    final sizzler = meleeById('sizzler');
    expect(sizzler.hook, isTrue);
    // The shop prices melees from worst to best: only the Scythe beats it.
    final ranked = [...kMelees]..sort((a, b) => b.price.compareTo(a.price));
    expect(ranked.map((m) => m.id).take(2), ['scythe', 'sizzler']);
    expect(sizzler.damage, lessThan(meleeById('scythe').damage));
  });

  test('skin boxes give rare skins less often', () {
    final rnd = Random(4);
    final counts = <Rarity, int>{};
    for (var i = 0; i < 4000; i++) {
      final prize = openSkinBox(rnd);
      expect(kWeaponIds, contains(prize.weapon));
      counts[prize.skin.rarity] = (counts[prize.skin.rarity] ?? 0) + 1;
    }
    expect(counts[Rarity.common]!, greaterThan(counts[Rarity.rare]!));
    expect(counts[Rarity.rare]!, greaterThan(counts[Rarity.epic]!));
    expect(counts[Rarity.epic]!, greaterThan(counts[Rarity.legendary]!));
    expect(counts[Rarity.legendary]!, greaterThan(0));
    expect(counts[Rarity.legendary]!, greaterThan(counts[Rarity.mythic]!));
    expect(counts[Rarity.mythic]!, greaterThan(0));
  });

  test('skins survive saving and loading', () async {
    final save = OutplaySave.instance;
    save.skins = {'assault_rifle:gold', 'fist:galaxy'};
    save.equippedSkins = {'assault_rifle': 'gold', 'knife': 'lava'};
    await save.save();
    save.skins = {};
    save.equippedSkins = {};
    await save.load();
    expect(save.ownsSkin('assault_rifle', 'gold'), isTrue);
    expect(save.skinOn('assault_rifle')?.name, 'Gold');
    // You can't wear a skin you don't own.
    expect(save.skinOn('knife'), isNull);
  });

  testWidgets('opening a skin box costs coins and gives a skin', (
    tester,
  ) async {
    await _phone(tester);
    final save = OutplaySave.instance
      ..coins = 400
      ..skins = {}
      ..equippedSkins = {};
    await save.save();
    await tester.pumpWidget(const MaterialApp(home: OutplayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skins'));
    await tester.pumpAndSettle();
    expect(find.text('Skin Box'), findsOneWidget);
    await tester.tap(find.textContaining('OPEN'));
    await tester.pump();
    expect(find.text('Opening…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Close'), findsOneWidget);
    expect(save.skins, hasLength(1));
    expect(save.coins, 400 - kSkinBoxPrice);
    await tester.tap(find.text('WEAR IT'));
    await tester.pumpAndSettle();
    final won = save.skins.single.split(':');
    expect(save.equippedSkins[won[0]], won[1]);
  });

  testWidgets('the skin button on a weapon card switches its skin', (
    tester,
  ) async {
    await _phone(tester);
    final save = OutplaySave.instance
      ..coins = 0
      ..skins = {'assault_rifle:galaxy'}
      ..equippedSkins = {};
    await save.save();
    await tester.pumpWidget(const MaterialApp(home: OutplayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guns'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.brush_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Assault Rifle skins'), findsOneWidget);
    await tester.tap(find.text('Galaxy'));
    await tester.pumpAndSettle();
    expect(save.equippedSkins['assault_rifle'], 'galaxy');
    expect(find.text('Wearing'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets('you can unlock a second melee slot and put the Sizzler in it', (
    tester,
  ) async {
    await _phone(tester);
    final save = OutplaySave.instance
      ..coins = 500
      ..ownedMelees = {'fist', 'sizzler'}
      ..melee = 'fist'
      ..meleeSlot2 = false
      ..melee2 = null;
    await save.save();
    await tester.pumpWidget(const MaterialApp(home: OutplayScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Carry two melees'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, '$kSecondMeleePrice').last,
    );
    await tester.pumpAndSettle();
    expect(save.meleeSlot2, isTrue);
    expect(save.melee2, 'sizzler');
    expect(save.coins, 500 - kSecondMeleePrice);
    expect(find.text('MELEE 2'), findsOneWidget);
    save.melee2 = null;
    await save.save();
    await save.load();
    expect(save.meleeSlot2, isTrue);
    save.melee2 = 'sizzler';
    await save.save();
    await save.load();
    expect(save.melee2, 'sizzler');
  });

  testWidgets('the Sizzler in melee slot 2 has a PULL button', (tester) async {
    await _phone(tester);
    final save = OutplaySave.instance
      ..ownedMelees = {'fist', 'sizzler'}
      ..melee = 'fist'
      ..meleeSlot2 = true
      ..melee2 = 'sizzler';
    await save.save();
    await tester.pumpWidget(
      const MaterialApp(
        home: OutplayGameScreen(mode: OutplayMode.duel, mapId: 'warehouse'),
      ),
    );
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('PULL'), findsNothing);
    await tester.tap(find.text('Sizzler'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('PULL'), findsOneWidget);
    await tester.tap(find.text('PULL'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('PULL'), findsNothing);
    expect(find.text('4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('the RPG Mini fires rockets as fast as a minigun', () {
    final rpg = gunById('rpg_mini');
    expect(rpg.kind, ShotKind.ball);
    expect(rpg.splash, greaterThan(0));
    expect(rpg.fireInterval, lessThan(0.1));
  });

  test('Mythic skins only come for their own weapon', () {
    final rnd = Random(9);
    for (var i = 0; i < 3000; i++) {
      final prize = openSkinBox(rnd);
      expect(prize.skin.fits(prize.weapon), isTrue);
    }
    expect(skinById('fighter_jet')!.fits('rpg_mini'), isTrue);
    expect(skinById('fighter_jet')!.fits('assault_rifle'), isFalse);
    expect(skinById('rock_machine')!.fits('slapper_machine'), isTrue);
    expect(skinById('rock_machine')!.fits('fist'), isFalse);
  });

  test('avatars survive saving and loading', () async {
    final save = OutplaySave.instance;
    save.name = 'Oscar';
    save.avatar = const Avatar(skin: 4, shirt: 2, hat: 3, face: 2);
    await save.save();
    save.name = '';
    save.avatar = const Avatar();
    await save.load();
    expect(save.name, 'Oscar');
    expect(save.avatar.toList(), [4, 2, 11, 1, 0, 3, 2]);
    // Junk from an old or broken save becomes a normal player.
    expect(Avatar.fromList('nope').toList(), const Avatar().toList());
  });

  testWidgets('you need a name before saving your player', (tester) async {
    await _phone(tester);
    OutplaySave.instance.name = '';
    await tester.pumpWidget(const MaterialApp(home: OutplayAvatarScreen()));
    expect(find.text('TYPE A NAME FIRST'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Oscar');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Crown'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Crown'));
    await tester.pump();
    await tester.ensureVisible(find.text('SAVE MY PLAYER'));
    await tester.tap(find.text('SAVE MY PLAYER'));
    await tester.pump();
    expect(OutplaySave.instance.name, 'Oscar');
    expect(OutplaySave.instance.avatar.hat, kHats.indexOf('Crown'));
  });

  test('joining a room code nobody made says so', () async {
    final hub = LoopbackHub();
    expect(
      () => OutplayRoom.join(hub.makeLink, 'ZZZZ'),
      throwsA(contains('No room with the code ZZZZ')),
    );
  });

  test('old saves drop guns that were removed', () async {
    SharedPreferences.setMockInitialValues({
      'outplay_save':
          '{"coins":5,"guns":["assault_rifle","minigun"],"melees":["fist"],'
          '"primary":"minigun","secondary":null,"melee":"fist","slot2":false}',
    });
    final s = OutplaySave.instance;
    await s.load();
    expect(s.ownedGuns, {'assault_rifle'});
    expect(s.primary, 'assault_rifle');
  });
}
