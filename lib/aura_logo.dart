import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

class AuraLogo extends StatelessWidget {
  const AuraLogo({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Aura',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.auraSurface,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: CustomPaint(painter: _AuraMark(context.auraAccent)),
      ),
    ),
  );
}

class _AuraMark extends CustomPainter {
  const _AuraMark(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(106, 106, 300, 300),
      math.pi / 4,
      math.pi * 1.5,
      false,
      stroke,
    );
    canvas.drawLine(const Offset(216, 232), const Offset(216, 280), stroke);
    canvas.drawLine(const Offset(256, 192), const Offset(256, 320), stroke);
    canvas.drawLine(const Offset(296, 232), const Offset(296, 280), stroke);
    canvas.drawCircle(const Offset(406, 256), 18, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AuraMark oldDelegate) => color != oldDelegate.color;
}
