import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How many game screens are being played right now. While one is, a
/// tablet or phone lets the game use the whole screen instead of the
/// phone-width column the menus sit in.
final ValueNotifier<int> gamesPlaying = ValueNotifier(0);

/// Tablets and phones (not computers) give games the whole screen. We
/// can't trust the browser's name for the device (iPads say they are Macs),
/// so a device counts as a tablet once it has been touched.
bool get bigGameScreens =>
    _touched ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

bool _touched = false;

/// Starts watching for touches. Call once when the app starts.
void watchForTouch() {
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event.kind == PointerDeviceKind.touch) _touched = true;
  });
}

/// Add to the State of a screen where you actually play, so it gets the
/// whole screen on tablets.
mixin FullScreenGame<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    _change(1);
  }

  @override
  void dispose() {
    _change(-1);
    super.dispose();
  }

  // Wait for the frame to finish: the app frame rebuilds when this changes.
  static void _change(int by) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => gamesPlaying.value += by)
      ..scheduleFrame();
  }
}
