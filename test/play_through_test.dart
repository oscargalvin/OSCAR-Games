// Slow (about 10 minutes): taps and swipes randomly through every game at
// phone sizes, upright and sideways, and fails on any overflow or crash.
// Skipped by default; run with: flutter test --run-skipped -t slow
@Tags(['slow'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oscar_games/main.dart';
import 'package:oscar_games/theme/app_theme.dart';
import 'package:oscar_games/screens/home_screen.dart';
import 'package:oscar_games/services/save_service.dart';
import 'package:oscar_games/games/board_game/board_game_screen.dart';
import 'package:oscar_games/games/boat_fishing/boat_fishing_screen.dart';
import 'package:oscar_games/games/fly_or_crash/fly_or_crash_screen.dart';
import 'package:oscar_games/games/memory_match/memory_match_screen.dart';
import 'package:oscar_games/games/outplay/outplay_avatar.dart';
import 'package:oscar_games/games/outplay/outplay_game.dart';
import 'package:oscar_games/games/outplay/outplay_screen.dart';
import 'package:oscar_games/games/reaction/reaction_screen.dart';
import 'package:oscar_games/games/snake/snake_screen.dart';
import 'package:oscar_games/games/target_shooter/models/game_world.dart';
import 'package:oscar_games/games/target_shooter/models/player_data.dart';
import 'package:oscar_games/games/target_shooter/shop_screen.dart';
import 'package:oscar_games/games/target_shooter/target_game_screen.dart';
import 'package:oscar_games/games/target_shooter/world_select_screen.dart';
import 'package:oscar_games/games/tic_tac_toe/tic_tac_toe_screen.dart';

const _paris = Destination('Paris', 'France', 48.86, 2.35);

final _screens = <String, Widget Function()>{
  'home': () => const HomeScreen(),
  'fly_or_crash': () => const FlyOrCrashScreen(),
  'flight': () => const FlightScreen(destination: _paris),
  'cartoon_flight': () => const CartoonFlightScreen(destination: _paris),
  'attendant': () => const AttendantScreen(destination: _paris),
  'outplay': () => const OutplayScreen(),
  'outplay_zone': () => const OutplayGameScreen(),
  'outplay_player': () => const OutplayAvatarScreen(),
  'outplay_mansion': () => const OutplayGameScreen(
    mode: OutplayMode.freeForAll,
    mapId: 'mansion',
    bots: 5,
  ),
  'outplay_crocs': () =>
      const OutplayGameScreen(mode: OutplayMode.duel, mapId: 'crocs'),
  'outplay_duel': () =>
      const OutplayGameScreen(mode: OutplayMode.duel, mapId: 'volcano'),
  'outplay_ffa': () => const OutplayGameScreen(
    mode: OutplayMode.freeForAll,
    mapId: 'runway',
    bots: 9,
  ),
  'board_game': () => const BoardGameScreen(),
  'boat_fishing': () => const BoatFishingScreen(),
  'tic_tac_toe': () => const TicTacToeScreen(),
  'memory_match': () => const MemoryMatchScreen(),
  'snake': () => const SnakeScreen(),
  'reaction': () => const ReactionScreen(),
  'target_worlds': () => const WorldSelectScreen(),
  'target_shop': () =>
      ShopScreen(playerData: PlayerData.fromSave(), onUpdate: () {}),
  'target_game': () => TargetGameScreen(
    world: GameWorld.worlds.first,
    playerData: PlayerData.fromSave(),
    onComplete: () {},
  ),
};

/// Tests render text with a blocky placeholder font that is much wider than
/// real text, so load the Roboto that the web build falls back to.
Future<void> _loadRealFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final roboto = dir.listSync().whereType<File>().where(
    (f) => RegExp(r'Roboto-[A-Za-z]+\.ttf$').hasMatch(f.path),
  );
  for (final family in ['Roboto', 'Inter']) {
    final loader = FontLoader(family);
    for (final f in roboto) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('${dir.path}/MaterialIcons-Regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

void main() {
  setUpAll(_loadRealFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SaveService.instance.init();
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(375, 667),
    const Size(640, 360),
  ]) {
    for (final screen in _screens.entries) {
      testWidgets(
        'play through ${screen.key} ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final problems = <String>{};
          final oldHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            final msg = details.exceptionAsString().split('\n').first;
            final where = RegExp(
              r'lib/[\w/]+\.dart:\d+',
            ).firstMatch(details.toString())?.group(0);
            problems.add('$msg at $where');
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              builder: (context, child) => OscarGamesApp.frame(child),
              home: screen.value(),
            ),
          );
          final rnd = Random(size.width.toInt() + screen.key.length);
          for (var i = 0; i < 250; i++) {
            final p = Offset(
              rnd.nextDouble() * size.width,
              60 + rnd.nextDouble() * (size.height - 60),
            );
            try {
              await tester.tapAt(p);
              if (rnd.nextInt(5) == 0) {
                await tester.dragFrom(
                  p,
                  Offset(
                    rnd.nextDouble() * 200 - 100,
                    rnd.nextDouble() * 200 - 100,
                  ),
                );
              }
              await tester.pump(const Duration(milliseconds: 250));
            } catch (e) {
              problems.add('threw: ${e.toString().split('\n').first}');
            }
          }
          FlutterError.onError = oldHandler;
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 10));
          expect(problems, isEmpty, reason: problems.join('\n'));
        },
      );
    }
  }
}
