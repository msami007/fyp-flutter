import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/HearingProfileService.dart';
import '../../data/services/audio_enhancement_service.dart';
import 'live_assist_screen.dart';
import 'transcription_screen.dart';
import 'conversation_history_screen.dart';
import 'hearing_test_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _profileLoaded = false;
  String _profileInfo = 'Loading profile...';
  String? _userId;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _loadProfile();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userId = prefs.getString('user_id');
      });
    }
  }

  Future<void> _loadProfile() async {
    final profile = await HearingProfileService().getLocalProfile();
    if (mounted) {
      setState(() {
        if (profile != null) {
          _profileLoaded = true;
          final leftGain = (profile['leftEarGain'] as num?)?.toStringAsFixed(2) ?? '?';
          final rightGain = (profile['rightEarGain'] as num?)?.toStringAsFixed(2) ?? '?';
          _profileInfo = 'Left: $leftGain  Right: $rightGain';
        } else {
          _profileLoaded = false;
          _profileInfo = 'No profile found';
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildWelcomeHeader(),
            const SizedBox(height: 40),
            _buildLiveAssistAction(),
            const SizedBox(height: 30),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "HEARWISE",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            Text(
              "Empowering your sound experience",
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        _buildCompactProfileStatus(),
      ],
    );
  }

  Widget _buildCompactProfileStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _profileLoaded ? Icons.verified : Icons.warning_amber_rounded,
            color: _profileLoaded ? Colors.greenAccent : Colors.orangeAccent,
            size: 14,
          ),
          const SizedBox(width: 8),
          Text(
            _profileLoaded ? "CALIBRATED" : "NOT TESTED",
            style: TextStyle(
              color: _profileLoaded ? Colors.greenAccent : Colors.orangeAccent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveAssistAction() {
    return Center(
      child: Column(
        children: [
          Text(
            "Ready to assist you",
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          ScaleTransition(
            scale: _pulseAnimation,
            child: GestureDetector(
              onTap: () {
                // Navigate to Live Assist tab in MainScreen
                // Since this is a simple app, we can just push the screen for now
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveAssistScreen()));
              },
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF8E87FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hearing_rounded, color: Colors.white, size: 64),
                    SizedBox(height: 8),
                    Text(
                      "START",
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                    Text(
                      "LIVE ASSIST",
                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        Row(
          children: [
            _buildActionCard(
              "Test Hearing",
              Icons.speed,
                  () {
                if (_userId != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => HearingTestScreen(userId: _userId!)));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User session not found')));
                }
              },
            ),
            const SizedBox(width: 16),
            _buildActionCard(
              "Live Caption",
              Icons.subtitles_rounded,
                  () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TranscriptionScreen()));
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildActionCard(
              "History",
              Icons.history_rounded,
                  () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ConversationHistoryScreen()));
              },
            ),
            const SizedBox(width: 16),
            _buildActionCard(
              "AI Settings",
              Icons.tune,
                  () {
                // Placeholder
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(String label, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2139),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF6C63FF), size: 28),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}