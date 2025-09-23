import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  Map<String, dynamic>? todayScore;
  Map<String, dynamic>? weekSummary;
  List<dynamic>? postureStats;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // 오늘의 자세 점수 가져오기
      final todayResponse = await http.get(
        Uri.parse('http://3.34.159.75:8766/statistics/score/today'),
        headers: {'Content-Type': 'application/json'},
      );

      // 주간 요약 데이터 가져오기 (최근 7일)
      final summaryResponse = await http.get(
        Uri.parse('http://3.34.159.75:8766/statistics/summary?days=7'),
        headers: {'Content-Type': 'application/json'},
      );

      // 자세별 통계 가져오기 (최근 7일)
      final postureResponse = await http.get(
        Uri.parse('http://3.34.159.75:8766/statistics/postures'),
        headers: {'Content-Type': 'application/json'},
      );

      if (todayResponse.statusCode == 200) {
        todayScore = jsonDecode(todayResponse.body);
      }

      if (summaryResponse.statusCode == 200) {
        weekSummary = jsonDecode(summaryResponse.body);
      }

      if (postureResponse.statusCode == 200) {
        postureStats = jsonDecode(postureResponse.body);
      }

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = '데이터를 불러오는 중 오류가 발생했습니다: $e';
      });
      print('API 오류: $e');
    }
  }

  Future<void> _resetStatistics() async {
    // 확인 다이얼로그 표시
    bool confirm = await _showResetConfirmDialog();
    if (!confirm) return;

    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final response = await http.delete(
        Uri.parse('http://3.34.159.75:8766/data/reset?confirm=true'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        // 초기화 성공 - 데이터 다시 로드
        await _loadReportData();

        // 성공 메시지 표시
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('모든 통계 데이터가 초기화되었습니다.'),
                ],
              ),
              backgroundColor: Color(0xFF48BB78),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = '데이터 초기화 중 오류가 발생했습니다: $e';
      });

      // 오류 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('초기화 실패: $e'),
              ],
            ),
            backgroundColor: Color(0xFFE53E3E),
            duration: Duration(seconds: 3),
          ),
        );
      }
      print('초기화 오류: $e');
    }
  }

  Future<bool> _showResetConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.warning, color: Color(0xFFE53E3E), size: 28),
                  SizedBox(width: 12),
                  Text(
                    '데이터 초기화',
                    style: TextStyle(
                      color: Color(0xFF2D3748),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '모든 자세 측정 데이터가 영구적으로 삭제됩니다.',
                    style: TextStyle(
                      color: Color(0xFF2D3748),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(0xFFE53E3E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFFE53E3E),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '이 작업은 되돌릴 수 없습니다.',
                            style: TextStyle(
                              color: Color(0xFFE53E3E),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    '취소',
                    style: TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFE53E3E),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    '초기화',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFF0F7FF), const Color(0xFFF8FAFC)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Color(0xFF4A90E2),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📊 주간 리포트',
                            style: TextStyle(
                              color: const Color(0xFF2D3748),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '자세 통계 및 개선 분석',
                            style: TextStyle(
                              color: const Color(0xFF718096),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 초기화 버튼
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: _resetStatistics,
                        icon: Icon(
                          Icons.delete_outline,
                          color: const Color(0xFFE53E3E),
                          size: 20,
                        ),
                        tooltip: '모든 데이터 초기화',
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 새로고침 버튼
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: _loadReportData,
                        icon: Icon(
                          Icons.refresh,
                          color: const Color(0xFF4A90E2),
                          size: 20,
                        ),
                        tooltip: '데이터 새로고침',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                Expanded(
                  child:
                      isLoading
                          ? _buildLoadingState()
                          : errorMessage != null
                          ? _buildErrorState()
                          : _buildReportContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
          ),
          const SizedBox(height: 16),
          Text(
            '리포트 데이터를 불러오는 중...',
            style: TextStyle(
              color: const Color(0xFF718096),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: const Color(0xFFE53E3E), size: 64),
          const SizedBox(height: 16),
          Text(
            '데이터를 불러올 수 없습니다',
            style: TextStyle(
              color: const Color(0xFF2D3748),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ?? '',
            style: TextStyle(
              color: const Color(0xFF718096),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadReportData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh, size: 20),
                const SizedBox(width: 8),
                Text('다시 시도'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // 오늘의 자세 점수 카드
          _buildTodayScoreCard(),
          const SizedBox(height: 24),

          // 주간 요약 카드
          _buildWeekSummaryCard(),
          const SizedBox(height: 24),

          // 자세별 통계 카드
          _buildPostureStatsCard(),
          const SizedBox(height: 24),

          // 개선 팁 카드
          _buildImprovementTipsCard(),
        ],
      ),
    );
  }

  Widget _buildTodayScoreCard() {
    if (todayScore == null) {
      return _buildPlaceholderCard('오늘의 자세 점수', '데이터 없음');
    }

    int score = todayScore!['total_score'] ?? 0;
    String grade = todayScore!['grade'] ?? 'N/A';
    String feedback = todayScore!['feedback'] ?? '';
    double goodPosturePercentage =
        todayScore!['good_posture_percentage'] ?? 0.0;

    Color scoreColor = _getScoreColor(score);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scoreColor, scoreColor.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scoreColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.today, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                '오늘의 자세 점수',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '$score',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '점',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    grade,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '바른 자세',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${goodPosturePercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (feedback.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                feedback,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeekSummaryCard() {
    if (weekSummary == null) {
      return _buildPlaceholderCard('주간 요약', '데이터 없음');
    }

    double goodPosturePercentage =
        weekSummary!['good_posture_percentage'] ?? 0.0;
    double totalTime = weekSummary!['total_monitoring_time'] ?? 0.0;
    int totalSessions = weekSummary!['total_sessions'] ?? 0;
    String mostProblematicPosture =
        weekSummary!['most_problematic_posture'] ?? 'N/A';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF48BB78).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.timeline,
                  color: Color(0xFF48BB78),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '📈 주간 요약 (7일)',
                style: TextStyle(
                  color: const Color(0xFF2D3748),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 주요 지표들
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  '바른 자세 비율',
                  '${goodPosturePercentage.toStringAsFixed(1)}%',
                  const Color(0xFF48BB78),
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryItem(
                  '총 모니터링',
                  '${(totalTime / 60).toStringAsFixed(1)}시간',
                  const Color(0xFF4A90E2),
                  Icons.access_time,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  '총 세션 수',
                  '$totalSessions회',
                  const Color(0xFFED8936),
                  Icons.bar_chart,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryItem(
                  '주요 문제 자세',
                  mostProblematicPosture,
                  const Color(0xFFE53E3E),
                  Icons.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF718096),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostureStatsCard() {
    if (postureStats == null || postureStats!.isEmpty) {
      return _buildPlaceholderCard('자세별 분석', '데이터 없음');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFED8936).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.assessment,
                  color: Color(0xFFED8936),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '🎯 자세별 분석',
                style: TextStyle(
                  color: const Color(0xFF2D3748),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...postureStats!
              .map(
                (posture) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPostureItem(
                    '${posture['posture_name']} (${posture['posture_id']}번)',
                    '${posture['percentage']?.toStringAsFixed(1) ?? '0.0'}%',
                    _getPostureColor(posture['posture_id']),
                    '${posture['total_duration_minutes']?.toStringAsFixed(1) ?? '0.0'}분',
                  ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  Widget _buildImprovementTipsCard() {
    String tips = '';
    if (todayScore != null) {
      String worstPosture = todayScore!['worst_posture'] ?? '';
      if (worstPosture.isNotEmpty && worstPosture != 'null') {
        tips = _getImprovementTips(worstPosture);
      }
    }

    if (tips.isEmpty) {
      tips = '• 1시간마다 목과 어깨 스트레칭\n• 모니터 높이를 눈높이에 맞추기\n• 등받이에 완전히 기대어 앉기';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: Color(0xFF4A90E2),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '💡 개선 제안',
                style: TextStyle(
                  color: const Color(0xFF2D3748),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📝 맞춤형 권장사항',
                  style: TextStyle(
                    color: const Color(0xFF4A90E2),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tips,
                  style: TextStyle(
                    color: const Color(0xFF2D3748),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderCard(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, color: const Color(0xFF9CA3AF), size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF2D3748),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: const Color(0xFF9CA3AF),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostureItem(
    String name,
    String percentage,
    Color color,
    String duration,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: const Color(0xFF2D3748),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  duration,
                  style: TextStyle(
                    color: const Color(0xFF718096),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              percentage,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 90) return const Color(0xFF48BB78);
    if (score >= 80) return const Color(0xFF4A90E2);
    if (score >= 70) return const Color(0xFFED8936);
    return const Color(0xFFE53E3E);
  }

  Color _getPostureColor(int postureId) {
    switch (postureId) {
      case 0:
        return const Color(0xFF48BB78); // 바른 자세
      case 1:
        return const Color(0xFFE53E3E); // 거북목
      case 2:
        return const Color(0xFFED8936); // 목 숙이기
      case 3:
        return const Color(0xFFED8936); // 앞으로 당겨 기대기
      case 4:
        return const Color(0xFFED8936); // 오른쪽으로 기대기
      case 5:
        return const Color(0xFFED8936); // 왼쪽으로 기대기
      case 6:
        return const Color(0xFF9F7AEA); // 오른쪽 다리 꼬기
      case 7:
        return const Color(0xFF9F7AEA); // 왼쪽 다리 꼬기
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  String _getImprovementTips(String worstPosture) {
    switch (worstPosture) {
      case '거북목 자세':
        return '• 턱을 뒤로 당기고 목을 곧게 세우기\n• 모니터를 눈높이에 맞추기\n• 목 뒤 근육 강화 운동';
      case '목 숙이기':
        return '• 시선을 수평으로 유지하기\n• 휴대폰 사용 시 높이 조절\n• 목 뒤 스트레칭 자주하기';
      case '앞으로 당겨 기대기':
        return '• 등받이에 완전히 기대어 앉기\n• 복부 근력 강화 운동\n• 허리 지지대 사용 고려';
      case '오른쪽으로 기대기':
      case '왼쪽으로 기대기':
        return '• 양쪽 어깨 높이 맞추기\n• 의자 높이 조절하기\n• 측면 근육 스트레칭';
      case '오른쪽 다리 꼬기':
      case '왼쪽 다리 꼬기':
        return '• 양발을 바닥에 평평히 놓기\n• 다리 꼬는 습관 교정\n• 발목 돌리기 운동';
      default:
        return '• 1시간마다 목과 어깨 스트레칭\n• 모니터 높이를 눈높이에 맞추기\n• 등받이에 완전히 기대어 앉기';
    }
  }
}
