import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/save_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  /// The app fills the whole screen, so tablets get the full width whether
  /// they are held upright or sideways.
  static const double maxAppWidth = double.infinity;

  static Widget frame(Widget? child) {
    return Container(
      color: const Color(0xFF15172A),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxAppWidth),
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
