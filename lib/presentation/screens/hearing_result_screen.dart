import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../routes/app_routes.dart';

class HearingResultScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const HearingResultScreen({super.key, required this.profile});

  @override
  State<HearingResultScreen> createState() => _HearingResultScreenState();
}

class _HearingResultScreenState extends State<HearingResultScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  bool _leftEarExpanded = false;
  bool _rightEarExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getHearingQuality(double gain) {
    if (gain <= 0.4) return "Excellent";
    if (gain <= 0.6) return "Good";
    if (gain <= 0.8) return "Fair";
    return "Needs Attention";
  }

  Color _getQualityColor(double gain) {
    if (gain <= 0.4) return const Color(0xFF4CAF50);
    if (gain <= 0.6) return const Color(0xFF8BC34A);
    if (gain <= 0.8) return const Color(0xFFFF9800);
    return const Color(0xFFE91E63);
  }

  List<MapEntry<String, double>> _getLeftEarData() {
    return (widget.profile["frequencyMap"] as Map<String, dynamic>)
        .entries
        .where((e) => e.key.startsWith("L_"))
        .map((e) => MapEntry(e.key.substring(2), (e.value as num).toDouble()))
        .toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));
  }

  List<MapEntry<String, double>> _getRightEarData() {
    return (widget.profile["frequencyMap"] as Map<String, dynamic>)
        .entries
        .where((e) => e.key.startsWith("R_"))
        .map((e) => MapEntry(e.key.substring(2), (e.value as num).toDouble()))
        .toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));
  }

  void _navigateToHome() {
    Navigator.pushReplacementNamed(context, AppRoutes.main);
  }

  @override
  Widget build(BuildContext context) {
    final leftGain = widget.profile['leftEarGain'];
    final rightGain = widget.profile['rightEarGain'];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "HEARING PROFILE",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Success icon with animation
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.3),
                  end: Offset.zero,
                ).animate(_slideAnimation),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              const Text(
                "Test Complete!",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                "Your personalized audio profile is ready",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),

              const SizedBox(height: 32),

              // ── Audiogram Graph Section ──
              _buildSectionTitle("Audiogram Visualization"),
              const SizedBox(height: 16),
              _buildAudiogramGraph(),

              const SizedBox(height: 32),

              // Ear comparison cards
              Row(
                children: [
                  Expanded(
                    child: _buildEarCard(
                      "Left Ear",
                      leftGain,
                      Icons.hearing_rounded,
                      true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildEarCard(
                      "Right Ear",
                      rightGain,
                      Icons.hearing_rounded,
                      false,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Collapsible frequency sections
              _buildCollapsibleFrequencySection(
                "Left Ear",
                _getLeftEarData(),
                const Color(0xFF6C63FF),
                _leftEarExpanded,
                    () {
                  setState(() {
                    _leftEarExpanded = !_leftEarExpanded;
                  });
                },
              ),

              const SizedBox(height: 16),

              _buildCollapsibleFrequencySection(
                "Right Ear",
                _getRightEarData(),
                const Color(0xFF2196F3),
                _rightEarExpanded,
                    () {
                  setState(() {
                    _rightEarExpanded = !_rightEarExpanded;
                  });
                },
              ),

              const SizedBox(height: 32),


              const SizedBox(height: 24),

              // Info card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2139),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: Color(0xFF6C63FF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Your audio will be automatically adjusted based on this profile for an optimal listening experience.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.8),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Done button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _navigateToHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "Done",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildEarCard(String title, double gain, IconData icon, bool isLeft) {
    final quality = _getHearingQuality(gain);
    final color = _getQualityColor(gain);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(isLeft ? 0 : math.pi),
            child: Icon(
              icon,
              size: 32,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withOpacity(0.5),
              ),
            ),
            child: Text(
              quality,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "${(gain * 100).toInt()}%",
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            "Gain Level",
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleFrequencySection(
      String title,
      List<MapEntry<String, double>> data,
      Color accentColor,
      bool isExpanded,
      VoidCallback onTap,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          // Header - always visible
          ListTile(
            onTap: onTap,
            leading: Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            trailing: AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.expand_more_rounded,
                color: accentColor,
                size: 24,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),

          // Expandable content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  ...data.map((entry) => _buildFrequencyBar(
                    "${entry.key} Hz",
                    entry.value,
                    accentColor,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyBar(String frequency, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                frequency,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "${(value * 100).toInt()}%",
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildAudiogramGraph() {
    final leftData = _getLeftEarData();
    final rightData = _getRightEarData();

    return Container(
      height: 300,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: CustomPaint(
        painter: AudiogramPainter(
          leftPoints: leftData.map((e) => e.value).toList(),
          rightPoints: rightData.map((e) => e.value).toList(),
          frequencies: leftData.map((e) => e.key).toList(),
        ),
      ),
    );
  }
}

class AudiogramPainter extends CustomPainter {
  final List<double> leftPoints;
  final List<double> rightPoints;
  final List<String> frequencies;

  AudiogramPainter({
    required this.leftPoints,
    required this.rightPoints,
    required this.frequencies,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw Grid and Labels
    final double colWidth = size.width / (frequencies.isEmpty ? 1 : frequencies.length - 1);
    final double rowHeight = size.height / 5;

    for (int i = 0; i < frequencies.length; i++) {
      double x = i * colWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
      
      // Freq labels
      textPainter.text = TextSpan(
        text: frequencies[i],
        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height + 8));
    }

    for (int i = 0; i <= 5; i++) {
      double y = i * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    // Draw Lines
    _drawDataLine(canvas, size, leftPoints, const Color(0xFF6C63FF), true);
    _drawDataLine(canvas, size, rightPoints, const Color(0xFF2196F3), false);
  }

  void _drawDataLine(Canvas canvas, Size size, List<double> points, Color color, bool isLeft) {
    if (points.isEmpty) return;

    final paintLine = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintPoint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final double colWidth = size.width / (points.length - 1);

    for (int i = 0; i < points.length; i++) {
      // Invert Y because lower gain means more loss (clinically 0 is top)
      // Here 0 is 0 gain, 1 is max gain.
      double y = (1 - points[i]) * size.height;
      double x = i * colWidth;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      // Draw markers
      canvas.drawCircle(Offset(x, y), 5, paintPoint);
      canvas.drawCircle(Offset(x, y), 8, Paint()..color = color.withOpacity(0.2)..style = PaintingStyle.fill);
    }

    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
