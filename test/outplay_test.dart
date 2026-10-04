import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/outplay/outplay_data.dart';
import 'package:oscar_games/games/outplay/outplay_game.dart';

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

  for (final map in ['volcano', 'runway', 'courtyard']) {
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
