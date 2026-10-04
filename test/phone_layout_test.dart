import 'dart:io';

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

/// Common phone viewports (logical pixels): small Android, iPhone SE,
/// iPhone 14, and a large Android.
const _phones = <String, Size>{
  '320x568': Size(320, 568),
  '360x640': Size(360, 640),
  '375x667': Size(375, 667),
  '390x844': Size(390, 844),
  '412x915': Size(412, 915),
};

const _paris = Destination('Paris', 'France', 48.86, 2.35);

final _screens = <String, Widget Function()>{
  'home': () => const HomeScreen(),
  'fly_or_crash': () => const FlyOrCrashScreen(),
  'flight': () => const FlightScreen(destination: _paris),
  'cartoon_flight': () => const CartoonFlightScreen(destination: _paris),
  'attendant': () => const AttendantScreen(destination: _paris),
  'outplay': () => const OutplayScreen(),
  'outplay_zone': () => const OutplayGameScreen(),
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

  for (final phone in _phones.entries) {
    for (final screen in _screens.entries) {
      testWidgets('${screen.key} fits a ${phone.key} phone', (tester) async {
        tester.view.physicalSize = phone.value * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final overflows = <String>[];
        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          final msg = details.exceptionAsString();
          if (msg.contains('overflowed')) {
            final where = RegExp(
              r'lib/[\w/]+\.dart:\d+',
            ).firstMatch(details.toString())?.group(0);
            overflows.add('${msg.split('\n').first} at $where');
          } else {
            oldHandler?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = oldHandler);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) => OscarGamesApp.frame(child),
            home: screen.value(),
          ),
        );
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        FlutterError.onError = oldHandler;
        // Leave the screen so timers and tickers are disposed.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));

        expect(overflows, isEmpty, reason: overflows.toSet().join('\n'));
      });
    }
  }
}
