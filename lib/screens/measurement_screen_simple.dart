import 'package:flutter/material.dart';
import 'dart:math';

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  String _statusText = '연결 중...';
  String _posture = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 시뮬레이션을 위한 타이머
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isLoading = false;
        _statusText = '연결 완료 (시뮬레이션)';
        _posture = '정자세';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '자세 측정',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) ...[
                const CircularProgressIndicator(color: Colors.blueAccent),
                const SizedBox(height: 20),
                Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ] else ...[
                PostureCard(posture: _posture),
                const SizedBox(height: 20),
                Text(
                  _statusText,
                  style: const TextStyle(fontSize: 16, color: Colors.green),
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _updatePosture,
        label: const Text(
          '자세 업데이트',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.refresh),
        backgroundColor: _isLoading ? Colors.grey : Colors.blueAccent,
      ),
    );
  }

  void _updatePosture() {
    final postures = [
      '정자세',
      '오른쪽 다리꼬기',
      '왼쪽 다리꼬기',
      '등 기대고 엉덩이 앞으로',
      '거북목(폰 보면서 목 숙이기)',
      '오른쪽 팔걸이',
      '왼쪽 팔걸이',
      '목 앞으로 나오는(컴퓨터 할 때)',
    ];

    final random = Random();
    setState(() {
      _posture = postures[random.nextInt(postures.length)];
    });
  }
}

// 현재 자세를 표시하는 카드 위젯입니다.
class PostureCard extends StatelessWidget {
  final String posture;

  const PostureCard({super.key, required this.posture});

  @override
  Widget build(BuildContext context) {
    IconData postureIcon;
    Color iconColor;
    String postureDescription;

    switch (posture) {
      case '정자세':
        postureIcon = Icons.check_circle_outline;
        iconColor = Colors.green;
        postureDescription = '아주 좋은 자세입니다!';
        break;
      case '오른쪽 다리꼬기':
      case '왼쪽 다리꼬기':
        postureIcon = Icons.warning_amber;
        iconColor = Colors.orange;
        postureDescription = '자세를 바꿔주세요.';
        break;
      case '거북목(폰 보면서 목 숙이기)':
      case '목 앞으로 나오는(컴퓨터 할 때)':
        postureIcon = Icons.warning_amber;
        iconColor = Colors.red;
        postureDescription = '목을 펴고 시선을 앞으로 하세요.';
        break;
      default:
        postureIcon = Icons.help_outline;
        iconColor = Colors.grey;
        postureDescription = '알 수 없는 자세입니다.';
        break;
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(postureIcon, size: 80, color: iconColor),
            const SizedBox(height: 20),
            Text(
              posture,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              postureDescription,
              style: TextStyle(fontSize: 16, color: iconColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
