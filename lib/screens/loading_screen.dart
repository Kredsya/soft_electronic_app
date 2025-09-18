import 'package:flutter/material.dart';
import 'dart:math';
import 'package:soft_electronics/screens/home_screen.dart'; // HomeScreen을 import합니다.

// 이 위젯은 애니메이션을 포함하므로 StatefulWidget을 사용합니다.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

// SingleTickerProviderStateMixin을 추가하여 AnimationController를 사용할 수 있게 합니다.
class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 애니메이션 컨트롤러를 초기화합니다. 3초 동안 반복되도록 설정합니다.
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // 애니메이션 범위를 0도에서 360도(2 * pi)까지 설정합니다.
    _animation = Tween<double>(begin: 0.0, end: 2 * pi).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.linear, // 일정한 속도로 회전하도록 합니다.
      ),
    );

    // 3초 후에 메인 화면으로 이동합니다.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // 위젯이 아직 화면에 있는지 확인
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    // 위젯이 사라질 때 컨트롤러를 정리하여 메모리 누수를 방지합니다.
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // 가운데 별표 아이콘입니다.
                const Icon(Icons.star, size: 60, color: Colors.blueAccent),
                // 회전하는 텍스트입니다.
                Transform.rotate(
                  angle: _animation.value,
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 120), // 별표 위쪽에 배치합니다.
                    child: Text(
                      '척추 요정',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
