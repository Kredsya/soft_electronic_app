import 'package:flutter/material.dart';
import 'dart:math';

class LineChartPainter extends CustomPainter {
  final List<double> data;

  LineChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;

    final path = Path();
    final xStep = size.width / (data.length - 1);
    final yMax = data.reduce(max);
    final scaleY = size.height / yMax;

    path.moveTo(0, size.height - data[0] * scaleY);

    for (int i = 1; i < data.length; i++) {
      path.lineTo(xStep * i, size.height - data[i] * scaleY);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
