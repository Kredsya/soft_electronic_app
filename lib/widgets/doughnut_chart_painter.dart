import 'package:flutter/material.dart';
import 'dart:math';

class DoughnutChartPainter extends CustomPainter {
  final List<double> data;
  final List<Color> colors;

  DoughnutChartPainter({required this.data, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    double startAngle = -pi / 2;
    double total = data.reduce((a, b) => a + b);

    for (int i = 0; i < data.length; i++) {
      final sweepAngle = (data[i] / total) * 2 * pi;
      final paint =
          Paint()
            ..color = colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 30;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
