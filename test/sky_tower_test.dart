import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscar_games/games/sky_tower/sky_tower_game.dart';
import 'package:oscar_games/games/sky_tower/sky_tower_screen.dart';
import 'package:oscar_games/games/sky_tower/sky_tower_sim.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Waits until the sliding block is [gap] away from the tower's middle.
void _slideTo(TowerGame g, double gap) {
  for (var i = 0; i < 4000; i++) {
    final m = g.moving!;
    final now = g.alongX ? m.x - g.top.x : m.z - g.top.z;
    if ((now - gap).abs() < 0.03) return;
    g.step(1 / 240);
  }
  fail('the block never got there');
}

void main() {
  test('a perfect drop snaps on and keeps the block the same size', () {
    final g = TowerGame();
    _slideTo(g, 0.05);
    g.drop();
    expect(g.floors, 1);
    expect(g.top.x, g.stack.first.x);
    expect(g.top.w, kStartSize);
    expect(g.perfects, 1);
    expect(g.chunks, isEmpty);
    expect(g.events, contains(TowerEvent.perfect));
  });

  test('a sloppy drop chops off the overhang, which falls', () {
    final g = TowerGame();
    _slideTo(g, 1.0);
    g.drop();
    expect(g.floors, 1);
    final size = g.alongX ? g.top.d : g.top.w;
    // The next block slides the other way, so check the cut one.
    final cut = g.stack.last;
    expect(cut.w * cut.d, closeTo(kStartSize * (kStartSize - 1), 0.1));
    expect(size, greaterThan(0));
    expect(g.chunks, hasLength(1));
    final y0 = g.chunks.single.y;
    g.step(0.5);
    expect(g.chunks.single.y, lessThan(y0));
    expect(g.perfects, 0);
  });

  test('three perfects in a row grow the blocks back', () {
    final g = TowerGame();
    _slideTo(g, 1.2);
    g.drop();
    final small = g.top.w * g.top.d;
    for (var i = 0; i < 3; i++) {
      _slideTo(g, 0.02);
      g.drop();
    }
    expect(g.perfects, 3);
    expect(g.top.w * g.top.d, greaterThan(small));
    expect(g.events, contains(TowerEvent.grow));
  });

  test('missing the tower ends the game', () {
    final g = TowerGame();
    _slideTo(g, -3.6);
    g.drop();
    expect(g.over, isTrue);
    expect(g.moving, isNull);
    expect(g.floors, 0);
    g.drop(); // nothing more happens
    expect(g.floors, 0);
  });

  test('coins and the sky change as you climb', () {
    final g = TowerGame();
    for (var i = 0; i < 26; i++) {
      _slideTo(g, 0.02);
      g.drop();
    }
    expect(g.floors, 26);
    expect(g.coins, 26 + g.perfectTotal * 2);
    expect(skyName(g.floors), 'The Clouds');
    expect(skyName(60), 'Space');
    expect(g.speed, greaterThan(TowerGame().speed));
  });

  testWidgets('play screen: tap to start, tap to drop, game over card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    int? floors;
    await tester.pumpWidget(
      MaterialApp(home: SkyTowerGameScreen(onFinish: (f, c) => floors = f)),
    );
    expect(find.textContaining('TAP TO DROP'), findsOneWidget);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.textContaining('TAP TO DROP'), findsNothing);
    // Tap again and again: sooner or later a block misses.
    for (var i = 0; i < 300 && floors == null; i++) {
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 230));
    }
    expect(floors, isNotNull);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('TOWER DONE!'), findsOneWidget);
    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('TOWER DONE!'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('menu: buy and pick a block colour', (tester) async {
    SharedPreferences.setMockInitialValues({'sky_tower_save': '{"coins":150}'});
    TowerSave.instance
      ..coins = 0
      ..themes = {'rainbow'}
      ..theme = 'rainbow';
    await tester.pumpWidget(const MaterialApp(home: SkyTowerScreen()));
    await tester.pumpAndSettle();
    expect(find.text('150'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Candy'), 200);
    await tester.tap(find.text('Candy'));
    await tester.pumpAndSettle();
    expect(TowerSave.instance.theme, 'candy');
    expect(TowerSave.instance.coins, 50);
    expect(find.text('50'), findsOneWidget);
  });
}
