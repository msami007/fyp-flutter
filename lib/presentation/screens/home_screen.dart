import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/HearingProfileService.dart';
import '../../data/services/audio_enhancement_service.dart';
import 'live_assist_screen.dart';
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
            const SizedBox(height: 30),
            _buildProfileStatus(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "HearWise",
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Personalized Hearing Assistance",
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.5),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileStatus() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _profileLoaded ? Colors.greenAccent.withOpacity(0.1) : Colors.orangeAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _profileLoaded ? Icons.verified : Icons.warning_amber_rounded,
                  color: _profileLoaded ? Colors.greenAccent : Colors.orangeAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _profileLoaded ? "Hearing Profile Ready" : "Profile Incomplete",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _profileInfo,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          if (!_profileLoaded) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_userId != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => HearingTestScreen(userId: _userId!)));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User session not found')));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Take Hearing Test", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
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
    return Row(
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
          "AI Settings",
          Icons.tune,
          () {
            // Placeholder: Navigate to settings or profile
          },
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