import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/sound_service.dart';
import 'outplay_art.dart';
import 'outplay_data.dart';

const List<Color> kSkinTones = [
  Color(0xFFFFE0BD), Color(0xFFFFCC80), Color(0xFFF1C27D), //
  Color(0xFFD7A27A), Color(0xFFA9714B), Color(0xFF8D5524),
  Color(0xFF6B3E26), Color(0xFF9CCC65), Color(0xFF81D4FA),
];

const List<Color> kClothes = [
  Color(0xFFEF5350), Color(0xFFFF7043), Color(0xFFFFCA28), //
  Color(0xFF66BB6A), Color(0xFF26A69A), Color(0xFF4FC3F7),
  Color(0xFF42A5F5), Color(0xFF5C6BC0), Color(0xFFAB47BC),
  Color(0xFFEC407A), Color(0xFF8D6E63), Color(0xFF37474F),
  Color(0xFFFAFAFA), Color(0xFF212121),
];

const List<Color> kHairColours = [
  Color(0xFF3E2723), Color(0xFF6D4C41), Color(0xFFFFD54F), //
  Color(0xFFE65100), Color(0xFF212121), Color(0xFFBDBDBD),
  Color(0xFFEC407A), Color(0xFF42A5F5), Color(0xFF66BB6A),
];

const List<String> kHairStyles = ['Bald', 'Short', 'Spiky', 'Long', 'Mohawk'];
const List<String> kHats = [
  'None', 'Cap', 'Beanie', 'Crown', 'Top hat', 'Horns', 'Headphones', //
];
const List<String> kFaces = ['Smile', 'Grin', 'Shades', 'Angry', 'Wow'];

/// How a player looks. Every part is a number picking from a list above,
/// so it's tiny to save and to send to other players.
class Avatar {
  final int skin, shirt, pants, hair, hairColour, hat, face;

  const Avatar({
    this.skin = 1,
    this.shirt = 5,
    this.pants = 11,
    this.hair = 1,
    this.hairColour = 0,
    this.hat = 0,
    this.face = 0,
  });

  Color get skinColour => kSkinTones[skin % kSkinTones.length];
  Color get shirtColour => kClothes[shirt % kClothes.length];
  Color get pantsColour => kClothes[pants % kClothes.length];
  Color get hairPaint => kHairColours[hairColour % kHairColours.length];

  List<int> toList() => [skin, shirt, pants, hair, hairColour, hat, face];

  static Avatar fromList(Object? raw) {
    if (raw is! List || raw.length < 7) return const Avatar();
    int at(int i, int n) => ((raw[i] as num?)?.toInt() ?? 0).abs() % n;
    return Avatar(
      skin: at(0, kSkinTones.length),
      shirt: at(1, kClothes.length),
      pants: at(2, kClothes.length),
      hair: at(3, kHairStyles.length),
      hairColour: at(4, kHairColours.length),
      hat: at(5, kHats.length),
      face: at(6, kFaces.length),
    );
  }

  static Avatar random(Random r) => Avatar(
    skin: r.nextInt(kSkinTones.length),
    shirt: r.nextInt(kClothes.length),
    pants: r.nextInt(kClothes.length),
    hair: r.nextInt(kHairStyles.length),
    hairColour: r.nextInt(kHairColours.length),
    hat: r.nextInt(3) == 0 ? 1 + r.nextInt(kHats.length - 1) : 0,
    face: r.nextInt(kFaces.length),
  );

  Avatar copyWith({
    int? skin,
    int? shirt,
    int? pants,
    int? hair,
    int? hairColour,
    int? hat,
    int? face,
  }) => Avatar(
    skin: skin ?? this.skin,
    shirt: shirt ?? this.shirt,
    pants: pants ?? this.pants,
    hair: hair ?? this.hair,
    hairColour: hairColour ?? this.hairColour,
    hat: hat ?? this.hat,
    face: face ?? this.face,
  );
}

/// Draws a whole person filling [r] (about twice as tall as wide).
/// [step] swings the legs; [hurt] flashes them white.
void paintAvatar(
  Canvas c,
  Avatar a,
  Rect r, {
  bool facing = true,
  double step = 0,
  bool hurt = false,
}) {
  final w = r.width, h = r.height;
  final ink = Paint()
    ..color = kOutplayInk
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1, w * 0.04)
    ..strokeJoin = StrokeJoin.round;
  Paint fill(Color col) => Paint()..color = hurt ? Colors.white : col;
  final pants = fill(a.pantsColour);
  final shirt = fill(a.shirtColour);
  final skin = fill(a.skinColour);
  final hair = fill(a.hairPaint);

  // Legs.
  final legW = w * 0.2;
  for (final dx in [-1, 1]) {
    final lx = r.center.dx + dx * w * 0.13 - legW / 2 + dx * step;
    final leg = RRect.fromRectAndRadius(
      Rect.fromLTWH(lx, r.top + h * 0.6, legW, h * 0.4),
      Radius.circular(legW * 0.3),
    );
    c.drawRRect(leg, pants);
    c.drawRRect(leg, ink);
  }
  // Body and arms.
  final body = RRect.fromRectAndRadius(
    Rect.fromLTWH(r.left + w * 0.18, r.top + h * 0.3, w * 0.64, h * 0.34),
    Radius.circular(w * 0.12),
  );
  for (final dx in [-1, 1]) {
    final arm = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        r.center.dx + dx * w * 0.38 - w * 0.08,
        r.top + h * 0.32,
        w * 0.16,
        h * 0.26,
      ),
      Radius.circular(w * 0.08),
    );
    c.drawRRect(arm, shirt);
    c.drawRRect(arm, ink);
    // Hands.
    c.drawCircle(
      Offset(r.center.dx + dx * w * 0.38, r.top + h * 0.6),
      w * 0.07,
      skin,
    );
  }
  c.drawRRect(body, shirt);
  c.drawRRect(body, ink);

  // Head.
  final head = Offset(r.center.dx, r.top + h * 0.17);
  final hr = w * 0.24;
  final headRect = Rect.fromCircle(center: head, radius: hr);

  // Long hair hangs behind the head.
  if (a.hair == 3) {
    final back = RRect.fromRectAndRadius(
      Rect.fromLTWH(head.dx - hr * 1.1, head.dy - hr * 0.4, hr * 2.2, hr * 1.9),
      Radius.circular(hr * 0.5),
    );
    c.drawRRect(back, hair);
    c.drawRRect(back, ink);
  }
  c.drawCircle(head, hr, skin);
  c.drawCircle(head, hr, ink);

  if (!facing) {
    // The back of their head.
    if (a.hair != 0) {
      c.drawArc(headRect, pi * 0.85, pi * 1.3, true, hair);
      c.drawArc(headRect, pi * 0.85, pi * 1.3, false, ink);
    }
  } else {
    // Hair on top.
    switch (a.hair) {
      case 1: // short
      case 3: // long
        c.drawArc(headRect, pi, pi, true, hair);
        c.drawArc(headRect, pi, pi, false, ink);
        break;
      case 2: // spiky
        final p = Path()..moveTo(head.dx - hr, head.dy - hr * 0.1);
        for (var i = 0; i < 5; i++) {
          final x0 = head.dx - hr + i * hr * 0.4;
          p.lineTo(x0 + hr * 0.2, head.dy - hr * 1.45);
          p.lineTo(x0 + hr * 0.4, head.dy - hr * 0.75);
        }
        p.lineTo(head.dx + hr, head.dy - hr * 0.1);
        p.close();
        c.drawPath(p, hair);
        c.drawPath(p, ink);
        break;
      case 4: // mohawk
        final m = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            head.dx - hr * 0.2,
            head.dy - hr * 1.5,
            hr * 0.4,
            hr * 0.9,
          ),
          Radius.circular(hr * 0.15),
        );
        c.drawRRect(m, hair);
        c.drawRRect(m, ink);
        break;
    }
    _paintFace(c, a.face, head, hr, ink);
  }
  _paintHat(c, a.hat, head, hr, ink, facing);
}

void _paintFace(Canvas c, int face, Offset head, double hr, Paint ink) {
  final eye = Paint()..color = kOutplayInk;
  final l = head + Offset(-hr * 0.38, -hr * 0.05);
  final rr = head + Offset(hr * 0.38, -hr * 0.05);
  final mouth = head + Offset(0, hr * 0.42);
  switch (face) {
    case 2: // shades
      final glasses = Paint()..color = const Color(0xFF111111);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: l, width: hr * 0.62, height: hr * 0.36),
          Radius.circular(hr * 0.1),
        ),
        glasses,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: rr, width: hr * 0.62, height: hr * 0.36),
          Radius.circular(hr * 0.1),
        ),
        glasses,
      );
      c.drawLine(l, rr, ink);
      c.drawLine(
        mouth + Offset(-hr * 0.25, 0),
        mouth + Offset(hr * 0.25, -hr * 0.05),
        ink,
      );
      return;
    case 3: // angry
      c.drawCircle(l, hr * 0.13, eye);
      c.drawCircle(rr, hr * 0.13, eye);
      c.drawLine(
        l + Offset(-hr * 0.2, -hr * 0.3),
        l + Offset(hr * 0.15, -hr * 0.15),
        ink,
      );
      c.drawLine(
        rr + Offset(hr * 0.2, -hr * 0.3),
        rr + Offset(-hr * 0.15, -hr * 0.15),
        ink,
      );
      c.drawArc(
        Rect.fromCircle(center: mouth + Offset(0, hr * 0.2), radius: hr * 0.25),
        pi + 0.4,
        pi - 0.8,
        false,
        ink,
      );
      return;
    case 4: // wow
      c.drawCircle(l, hr * 0.17, eye);
      c.drawCircle(rr, hr * 0.17, eye);
      c.drawOval(
        Rect.fromCenter(center: mouth, width: hr * 0.26, height: hr * 0.34),
        eye,
      );
      return;
    case 1: // grin
      c.drawCircle(l, hr * 0.13, eye);
      c.drawCircle(rr, hr * 0.13, eye);
      final grin = Path()
        ..moveTo(mouth.dx - hr * 0.4, mouth.dy - hr * 0.12)
        ..quadraticBezierTo(
          mouth.dx,
          mouth.dy + hr * 0.45,
          mouth.dx + hr * 0.4,
          mouth.dy - hr * 0.12,
        )
        ..close();
      c.drawPath(grin, Paint()..color = Colors.white);
      c.drawPath(grin, ink);
      return;
    default: // smile
      c.drawCircle(l, hr * 0.13, eye);
      c.drawCircle(rr, hr * 0.13, eye);
      c.drawArc(
        Rect.fromCircle(center: head + Offset(0, hr * 0.25), radius: hr * 0.35),
        0.2,
        pi - 0.4,
        false,
        ink,
      );
  }
}

void _paintHat(
  Canvas c,
  int hat,
  Offset head,
  double hr,
  Paint ink,
  bool facing,
) {
  switch (hat) {
    case 1: // cap
      final cap = Paint()..color = const Color(0xFFE53935);
      final top = Rect.fromCircle(center: head, radius: hr * 1.02);
      c.drawArc(top, pi, pi, true, cap);
      c.drawArc(top, pi, pi, true, ink);
      if (facing) {
        final peak = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            head.dx - hr * 0.2,
            head.dy - hr * 0.12,
            hr * 1.4,
            hr * 0.24,
          ),
          Radius.circular(hr * 0.1),
        );
        c.drawRRect(peak, cap);
        c.drawRRect(peak, ink);
      }
      break;
    case 2: // beanie
      final b = Paint()..color = const Color(0xFF3949AB);
      final top = Rect.fromCircle(center: head, radius: hr * 1.04);
      c.drawArc(top, pi, pi, true, b);
      c.drawArc(top, pi, pi, true, ink);
      final band = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          head.dx - hr * 1.08,
          head.dy - hr * 0.3,
          hr * 2.16,
          hr * 0.34,
        ),
        Radius.circular(hr * 0.12),
      );
      c.drawRRect(band, Paint()..color = const Color(0xFF5C6BC0));
      c.drawRRect(band, ink);
      c.drawCircle(
        head + Offset(0, -hr * 1.1),
        hr * 0.22,
        Paint()..color = Colors.white,
      );
      break;
    case 3: // crown
      final gold = Paint()..color = const Color(0xFFFFC93C);
      final y = head.dy - hr * 0.7;
      final p = Path()
        ..moveTo(head.dx - hr * 0.75, y)
        ..lineTo(head.dx - hr * 0.85, y - hr * 0.75)
        ..lineTo(head.dx - hr * 0.4, y - hr * 0.35)
        ..lineTo(head.dx, y - hr * 0.9)
        ..lineTo(head.dx + hr * 0.4, y - hr * 0.35)
        ..lineTo(head.dx + hr * 0.85, y - hr * 0.75)
        ..lineTo(head.dx + hr * 0.75, y)
        ..close();
      c.drawPath(p, gold);
      c.drawPath(p, ink);
      break;
    case 4: // top hat
      final black = Paint()..color = const Color(0xFF212121);
      final brim = Rect.fromCenter(
        center: head + Offset(0, -hr * 0.7),
        width: hr * 2.4,
        height: hr * 0.3,
      );
      final tube = Rect.fromLTWH(
        head.dx - hr * 0.7,
        head.dy - hr * 1.9,
        hr * 1.4,
        hr * 1.25,
      );
      c.drawRect(tube, black);
      c.drawRect(tube, ink);
      c.drawRect(
        Rect.fromLTWH(
          tube.left,
          tube.bottom - hr * 0.35,
          tube.width,
          hr * 0.25,
        ),
        Paint()..color = const Color(0xFFE53935),
      );
      c.drawRect(brim, black);
      c.drawRect(brim, ink);
      break;
    case 5: // horns
      final horn = Paint()..color = const Color(0xFFEEEEEE);
      for (final dx in [-1.0, 1.0]) {
        final p = Path()
          ..moveTo(head.dx + dx * hr * 0.45, head.dy - hr * 0.75)
          ..quadraticBezierTo(
            head.dx + dx * hr * 1.2,
            head.dy - hr * 1.0,
            head.dx + dx * hr * 1.05,
            head.dy - hr * 1.7,
          )
          ..lineTo(head.dx + dx * hr * 0.75, head.dy - hr * 0.55)
          ..close();
        c.drawPath(p, horn);
        c.drawPath(p, ink);
      }
      break;
    case 6: // headphones
      final band = Paint()
        ..color = const Color(0xFF212121)
        ..style = PaintingStyle.stroke
        ..strokeWidth = hr * 0.22;
      c.drawArc(
        Rect.fromCircle(center: head, radius: hr * 1.08),
        pi,
        pi,
        false,
        band,
      );
      for (final dx in [-1.0, 1.0]) {
        final cup = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: head + Offset(dx * hr * 1.02, 0),
            width: hr * 0.45,
            height: hr * 0.75,
          ),
          Radius.circular(hr * 0.2),
        );
        c.drawRRect(cup, Paint()..color = const Color(0xFFE53935));
        c.drawRRect(cup, ink);
      }
      break;
  }
}

/// A standing picture of an avatar, for menus.
class AvatarPreview extends StatelessWidget {
  final Avatar avatar;
  final double height;
  final bool facing;

  const AvatarPreview({
    super.key,
    required this.avatar,
    this.height = 80,
    this.facing = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * 0.62,
      height: height,
      child: CustomPaint(painter: _AvatarPainter(avatar, facing)),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final Avatar avatar;
  final bool facing;
  _AvatarPainter(this.avatar, this.facing);

  @override
  void paint(Canvas canvas, Size size) {
    // Leave room above the head for tall hats.
    final top = size.height * 0.16;
    final h = size.height - top;
    final w = h * 0.5;
    paintAvatar(
      canvas,
      avatar,
      Rect.fromLTWH((size.width - w) / 2, top, w, h),
      facing: facing,
    );
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.avatar != avatar || old.facing != facing;
}

/// Pick a name and make your own player.
class OutplayAvatarScreen extends StatefulWidget {
  const OutplayAvatarScreen({super.key});

  @override
  State<OutplayAvatarScreen> createState() => _OutplayAvatarScreenState();
}

class _OutplayAvatarScreenState extends State<OutplayAvatarScreen> {
  final _save = OutplaySave.instance;
  late Avatar _a = _save.avatar;
  late final _name = TextEditingController(text: _save.name);
  bool _front = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().length >= 2;

  void _done() {
    if (!_nameOk) return;
    _save.name = _name.text.trim();
    _save.avatar = _a;
    _save.save();
    SoundService.instance.play(GameSound.place);
    Navigator.of(context).pop(true);
  }

  void _set(Avatar a) {
    SoundService.instance.play(GameSound.tap);
    setState(() => _a = a);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
    ),
  );

  Widget _swatches(
    List<Color> colours,
    int selected,
    void Function(int) pick,
  ) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < colours.length; i++)
        GestureDetector(
          onTap: () => pick(i),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colours[i],
              shape: BoxShape.circle,
              border: Border.all(
                color: i == selected ? Colors.white : Colors.black26,
                width: i == selected ? 3 : 1,
              ),
            ),
            child: i == selected
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: colours[i].computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        ),
    ],
  );

  Widget _chips(List<String> names, int selected, void Function(int) pick) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < names.length; i++)
            ChoiceChip(
              label: Text(names[i]),
              selected: i == selected,
              onSelected: (_) => pick(i),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B2138),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B2138),
        title: const Text(
          'MY PLAYER',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              height: 170,
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF5B3FA8), Color(0xFF2E2A5C)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                children: [
                  Center(
                    child: AvatarPreview(
                      avatar: _a,
                      height: 150,
                      facing: _front,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: IconButton(
                      tooltip: 'Turn around',
                      onPressed: () => setState(() => _front = !_front),
                      icon: const Icon(
                        Icons.threesixty_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: IconButton(
                      tooltip: 'Surprise me',
                      onPressed: () => _set(Avatar.random(Random())),
                      icon: const Icon(
                        Icons.casino_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  _label('Name'),
                  TextField(
                    controller: _name,
                    maxLength: 12,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type your name',
                      hintStyle: TextStyle(color: Colors.white38),
                      counterStyle: TextStyle(color: Colors.white38),
                      isDense: true,
                    ),
                  ),
                  _label('Skin'),
                  _swatches(
                    kSkinTones,
                    _a.skin,
                    (i) => _set(_a.copyWith(skin: i)),
                  ),
                  _label('Shirt'),
                  _swatches(
                    kClothes,
                    _a.shirt,
                    (i) => _set(_a.copyWith(shirt: i)),
                  ),
                  _label('Pants'),
                  _swatches(
                    kClothes,
                    _a.pants,
                    (i) => _set(_a.copyWith(pants: i)),
                  ),
                  _label('Hair'),
                  _chips(
                    kHairStyles,
                    _a.hair,
                    (i) => _set(_a.copyWith(hair: i)),
                  ),
                  const SizedBox(height: 8),
                  _swatches(
                    kHairColours,
                    _a.hairColour,
                    (i) => _set(_a.copyWith(hairColour: i)),
                  ),
                  _label('Hat'),
                  _chips(kHats, _a.hat, (i) => _set(_a.copyWith(hat: i))),
                  _label('Face'),
                  _chips(kFaces, _a.face, (i) => _set(_a.copyWith(face: i))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nameOk ? _done : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7),
                    foregroundColor: kOutplayInk,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _nameOk ? 'SAVE MY PLAYER' : 'TYPE A NAME FIRST',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
