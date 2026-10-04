import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/outplay/outplay_avatar.dart';
import 'package:oscar_games/games/outplay/outplay_data.dart';
import 'package:oscar_games/games/outplay/outplay_game.dart';
import 'package:oscar_games/games/outplay/outplay_net.dart';

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

  for (final map in ['volcano', 'runway', 'courtyard', 'mansion', 'crocs']) {
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
    final host = await OutplayRoom.host(hub.makeLink, 'crocs', kind: 'duel');
    final first = await OutplayRoom.join(hub.makeLink, host.code);
    expect(first.kind, 'duel');
    expect(first.mapId, 'crocs');
    expect(
      () => OutplayRoom.join(hub.makeLink, host.code),
      throwsA(contains('full')),
    );
  });

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
    for (var i = 0; i < 120 && find.text('HUMAN').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    await stick.up();
    await tester.tap(find.text('HUMAN'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Nobody else was looking, so we wait for someone in our own 1v1 room.
    expect(find.text('Looking for someone…'), findsOneWidget);
    expect(listed.single.kind, 'duel');
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
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Online 1v1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
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
