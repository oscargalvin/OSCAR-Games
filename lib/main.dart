import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/save_service.dart';
import 'widgets/full_screen_game.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  watchForTouch();
  await SaveService.instance.init();
  // Phones and tablets can be held either way up.
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.primaryDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const OscarGamesApp());
}

class OscarGamesApp extends StatelessWidget {
  const OscarGamesApp({super.key});

  static const double maxAppWidth = 500;

  /// Centres the app in a phone-width column on wide screens. On tablets
  /// the game you are playing gets the whole screen (menus stay narrow).
  static Widget frame(Widget? child) {
    return Container(
      color: const Color(0xFF15172A),
      child: Center(
        child: ValueListenableBuilder<int>(
          valueListenable: gamesPlaying,
          builder: (context, playing, column) => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: playing > 0 && bigGameScreens
                  ? double.infinity
                  : maxAppWidth,
            ),
            child: column,
          ),
          child: Container(
            decoration: const BoxDecoration(color: AppTheme.primaryDark),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OSCAR Games',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) => frame(child),
      home: const HomeScreen(),
    );
  }
}
