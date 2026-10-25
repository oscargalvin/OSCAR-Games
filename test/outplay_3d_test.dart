import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:oscar_games/games/boost_ball/boost_ball_3d.dart' show V3;
import 'package:oscar_games/games/outplay/outplay_3d.dart';
import 'package:oscar_games/games/outplay/outplay_avatar.dart';
import 'package:oscar_games/games/outplay/outplay_data.dart';

void main() {
  test('the 3D camera sees what is in front and not what is behind', () {
    // Standing at (5, 5) looking along the map's x.
    final s = Scene3D(
      op3(const Offset(5, 5), 0.5),
      opDir(0),
      300,
      const Offset(200, 150),
    );
    final ahead = s.project(op3(const Offset(8, 5), 0.5))!;
    expect(ahead.dx, closeTo(200, 0.01));
    expect(ahead.dy, closeTo(150, 0.01));
    expect(s.project(op3(const Offset(2, 5), 0.5)), isNull);
    // Further down the map (bigger y) is on your right when facing +x.
    expect(s.project(op3(const Offset(8, 6), 0.5))!.dx, greaterThan(200));
    // Higher up is higher on screen.
    expect(s.project(op3(const Offset(8, 5), 1))!.dy, lessThan(150));
  });

  test('blocks and flat drawings both get drawn', () {
    final s = Scene3D(
      const V3(0, 0, 0),
      const V3(1, 0, 0),
      300,
      const Offset(200, 150),
    );
    var drawn = 0;
    s.group(() {
      s.box(
        const V3(4, 0, 0),
        const V3(1, 0, 0),
        const V3(0, 1, 0),
        kUp,
        0.5,
        0.5,
        0.5,
        const Color(0xFFFF0000),
      );
    });
    final recorder = PictureRecorder();
    s.later(0, (_) => drawn++);
    s.draw(Canvas(recorder));
    expect(drawn, 1);
    recorder.endRecording();
  });

  test('every look of player and weapon draws in 3D', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (var hat = 0; hat < kHats.length; hat++) {
      for (var hair = 0; hair < kHairStyles.length; hair++) {
        paintAvatar3D(
          canvas,
          const Size(80, 100),
          Avatar(hat: hat, hair: hair, face: (hat + hair) % kFaces.length),
        );
      }
    }
    for (final look in WeaponLook.values) {
      paintWeaponIcon3D(
        canvas,
        const Size(100, 62),
        look,
        const Color(0xFF42A5F5),
      );
    }
    recorder.endRecording();
  });
}
