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
        backgroundColor: const Color(0xFF1E2139),
        title: const Text('Menu'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline_rounded, color: Colors.white),
            title: const Text('Profile Account', style: TextStyle(color: Colors.white)),
            subtitle: const Text('View account details', style: TextStyle(color: Colors.white70)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileAccountScreen())),
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.hearing_outlined, color: Colors.white),
            title: const Text('Hearing Profile', style: TextStyle(color: Colors.white)),
            subtitle: const Text('View saved hearing profile', style: TextStyle(color: Colors.white70)),
            onTap: _viewHearingProfile,
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.replay_outlined, color: Colors.white),
            title: const Text('Take Hearing Profile Again', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Re-run the hearing test', style: TextStyle(color: Colors.white70)),
            onTap: _takeHearingProfileAgain,
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.subtitles_outlined, color: Colors.white),
            title: const Text('Live Caption', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Start real-time transcription', style: TextStyle(color: Colors.white70)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TranscriptionScreen())),
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.history_rounded, color: Colors.white),
            title: const Text('Conversation History', style: TextStyle(color: Colors.white)),
            subtitle: const Text('View saved transcripts', style: TextStyle(color: Colors.white70)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConversationHistoryScreen())),
          ),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.bluetooth_rounded, color: Colors.white),
            title: const Text('Connect Devices', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Pair hearing aids or earbuds', style: TextStyle(color: Colors.white70)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectDeviceScreen())),
          ),
          const Divider(color: Colors.white10),
          
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white),
            title: const Text('Logout', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Sign out of your account', style: TextStyle(color: Colors.white70)),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Logout')),
                  ],
                ),
              );
              if (confirmed == true) await _logout();
            },
          ),
        ],
      ),
    );
  }
}
