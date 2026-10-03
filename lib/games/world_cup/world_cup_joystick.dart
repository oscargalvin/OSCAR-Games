import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Mobile-style virtual joystick — drag the knob to move (returns -1..1 direction).
class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    required this.onDirectionChanged,
    this.size = 120,
  });

  final ValueChanged<Offset> onDirectionChanged;
  final double size;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _knob = Offset.zero;
  bool _active = false;

  void _update(Offset local, Size area) {
    final center = Offset(area.width / 2, area.height / 2);
    final delta = local - center;
    final maxR = area.width / 2 - 18;
    final clamped = delta.distance <= maxR
        ? delta
        : Offset.fromDirection(delta.direction, maxR);
    final norm = Offset(
      (clamped.dx / maxR).clamp(-1.0, 1.0),
      (clamped.dy / maxR).clamp(-1.0, 1.0),
    );
    setState(() {
      _knob = clamped;
      _active = norm.distance > 0.08;
    });
    widget.onDirectionChanged(_active ? norm : Offset.zero);
  }

  void _reset() {
    setState(() {
      _knob = Offset.zero;
      _active = false;
    });
    widget.onDirectionChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _update(d.localPosition, Size(widget.size, widget.size)),
        onPanUpdate: (d) => _update(d.localPosition, Size(widget.size, widget.size)),
        onPanEnd: (_) => _reset(),
        onPanCancel: _reset,
        child: CustomPaint(
          painter: _JoystickPainter(knob: _knob, active: _active),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({required this.knob, required this.active});

  final Offset knob;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final knobCenter = center + knob;
    canvas.drawCircle(
      knobCenter,
      22,
      Paint()
        ..color = active ? AppTheme.accent : AppTheme.blue.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      knobCenter,
      22,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) =>
      oldDelegate.knob != knob || oldDelegate.active != active;
}

/// Default formation slots for home team (y=1 is own goal line, attacks toward y=0).
List<Offset> formation433Home() => const [
      Offset(0.50, 0.90),
      Offset(0.14, 0.74),
      Offset(0.36, 0.76),
      Offset(0.64, 0.76),
      Offset(0.86, 0.74),
      Offset(0.22, 0.58),
      Offset(0.50, 0.55),
      Offset(0.78, 0.58),
      Offset(0.22, 0.38),
      Offset(0.50, 0.34),
      Offset(0.78, 0.38),
    ];

List<Offset> formation433Away() =>
    formation433Home().map((p) => Offset(p.dx, 1 - p.dy)).toList();

Offset defaultPickSpawn({required bool userIsHome}) =>
    userIsHome ? const Offset(0.50, 0.55) : const Offset(0.50, 0.45);

Offset ballOffsetFromPlayer(Offset player, {required bool userIsHome}) {
  final dy = userIsHome ? -0.035 : 0.035;
  return Offset(player.dx, (player.dy + dy).clamp(0.06, 0.94));
}

double forwardMotion(Offset dir, {required bool userIsHome}) {
  final moveY = userIsHome ? dir.dy : -dir.dy;
  return max(0, -moveY);
}
