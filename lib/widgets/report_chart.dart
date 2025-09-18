import 'package:flutter/material.dart';

// 통계 차트를 보여주는 위젯입니다.
class ReportChart extends StatelessWidget {
  final String title;
  final Widget chart;
  final Widget legend;

  const ReportChart({
    super.key,
    required this.title,
    required this.chart,
    required this.legend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 20),
            chart,
            const SizedBox(height: 10),
            legend,
          ],
        ),
      ),
    );
  }
}
