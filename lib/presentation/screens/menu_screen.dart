import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/HearingProfileService.dart';
import 'hearing_test_screen.dart';
import 'hearing_result_screen.dart';
import 'profile_account_screen.dart';
import 'transcription_screen.dart';
import 'conversation_history_screen.dart';
import 'connect_device_screen.dart';
import '../../routes/app_routes.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getString('user_id');
    });
  }

  void _showSnack(String msg, [Color color = Colors.blue]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _viewHearingProfile() async {
    final hearingService = HearingProfileService();
    final profile = await hearingService.getLocalProfile();
    if (profile == null) {
      _showSnack('No local hearing profile found. You will be taken to the test.');
      if (_userId == null) return;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HearingTestScreen(userId: _userId!)),
      );
    } else {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HearingResultScreen(profile: profile)),
      );
    }
  }

  Future<void> _takeHearingProfileAgain() async {
    if (_userId == null) {
      _showSnack('User not found. Please login again.', Colors.red);
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HearingTestScreen(userId: _userId!)),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_id');
    await prefs.remove('hearing_profile');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMenuHeader(),
              const SizedBox(height: 48),
              
              _buildSectionTitle('ACCOUNT & HEARING'),
              const SizedBox(height: 16),
              _buildMenuCard([
                _buildMenuRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Profile Account',
                  subtitle: 'Manage your personal details',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileAccountScreen())),
                ),
                _buildMenuDivider(),
                _buildMenuRow(
                  icon: Icons.hearing_outlined,
                  title: 'Hearing Profile',
                  subtitle: 'View your optimization stats',
                  onTap: _viewHearingProfile,
                ),
                _buildMenuDivider(),
                _buildMenuRow(
                  icon: Icons.replay_rounded,
                  title: 'Re-take Hearing Test',
                  subtitle: 'Calibrate your audio profile',
                  onTap: _takeHearingProfileAgain,
                ),
              ]),
              
              const SizedBox(height: 32),
              _buildSectionTitle('CORE FEATURES'),
              const SizedBox(height: 16),
              _buildMenuCard([
                _buildMenuRow(
                  icon: Icons.subtitles_rounded,
                  title: 'Live Caption',
                  subtitle: 'Real-time speech to text',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TranscriptionScreen())),
                ),
                _buildMenuDivider(),
                _buildMenuRow(
                  icon: Icons.history_rounded,
                  title: 'Conversation History',
                  subtitle: 'Your saved transcripts',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConversationHistoryScreen())),
                ),
                _buildMenuDivider(),
                _buildMenuRow(
                  icon: Icons.bluetooth_rounded,
                  title: 'Connect Devices',
                  subtitle: 'Pair hearing aids or earbuds',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectDeviceScreen())),
                ),
              ]),
              
              const SizedBox(height: 40),
              _buildLogoutButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),
            const Text(
              'Menu & Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Text(
            'Personalize your hearing and transcription experience',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.3),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2442),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF6C63FF), size: 22),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.1),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Divider(
      color: Colors.white.withOpacity(0.03),
      height: 1,
      indent: 72,
      endIndent: 20,
    );
  }

  Widget _buildLogoutButton() {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF131932),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true), 
                  child: const Text('Logout', style: TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.bold))
                ),
              ],
            ),
          );
          if (confirmed == true) await _logout();
        },
        icon: const Icon(Icons.logout_rounded, color: Color(0xFFE91E63), size: 18),
        label: const Text(
          'LOGOUT FROM ACCOUNT',
          style: TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          backgroundColor: const Color(0xFFE91E63).withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
