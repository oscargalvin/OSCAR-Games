import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/games/outplay/outplay_data.dart';
import 'package:oscar_games/games/outplay/outplay_match.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OutplaySave.instance.load();
  });

  testWidgets('holding shoot plays a whole duel to the end', (tester) async {
    tester.view.physicalSize = const Size(375, 667) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final coinsBefore = OutplaySave.instance.coins;

    await tester.pumpWidget(const MaterialApp(home: OutplayMatchScreen()));
    // Hold a thumb on the right side: auto-aims and fires at the bot.
    final gesture = await tester.startGesture(const Offset(300, 400));
    var finished = false;
    for (var i = 0; i < 240 * 30 && !finished; i++) {
      await tester.pump(const Duration(milliseconds: 33));
      finished = find.text('VICTORY').evaluate().isNotEmpty ||
          find.text('DEFEAT').evaluate().isNotEmpty;
    }
    await gesture.up();
    expect(finished, isTrue, reason: 'match never ended');
    expect(OutplaySave.instance.coins, greaterThan(coinsBefore));
    await tester.pumpWidget(const SizedBox());
  });

  test('saves and reloads unlocks', () async {
    final s = OutplaySave.instance;
    s.coins = 999;
    s.ownedGuns.add('sniper');
    s.ownedMelees.add('scythe');
    s.secondSlot = true;
    s.secondary = 'sniper';
    s.melee = 'scythe';
    s.levels['sniper'] = 3;
    await s.save();
    s.coins = 0;
    s.ownedGuns = {'assault_rifle'};
    await s.load();
    expect(s.coins, 999);
    expect(s.ownedGuns, contains('sniper'));
    expect(s.melee, 'scythe');
    expect(s.levelOf('sniper'), 3);
  });
}
