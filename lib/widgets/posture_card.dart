import 'package:flutter/material.dart';

// 현재 자세를 표시하는 카드 위젯입니다.
class PostureCard extends StatelessWidget {
  final String posture;

  const PostureCard({
    super.key,
    required this.posture,
  });

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
              style: TextStyle(
                fontSize: 16,
                color: iconColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
