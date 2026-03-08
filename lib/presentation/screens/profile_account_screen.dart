import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileAccountScreen extends StatefulWidget {
  const ProfileAccountScreen({super.key});

  @override
  State<ProfileAccountScreen> createState() => _ProfileAccountScreenState();
}

class _ProfileAccountScreenState extends State<ProfileAccountScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: const Color(0xFF1E2139),
      ),
      backgroundColor: const Color(0xFF0A0E27),
      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Account Information', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              color: const Color(0xFF1E2139),
              child: ListTile(
                title: const Text('User ID', style: TextStyle(color: Colors.white)),
                subtitle: Text(_userId ?? 'Not available', style: const TextStyle(color: Colors.white70)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Additional account details will appear here.', style: TextStyle(color: Colors.white54)),
          ],
        ),
        ),
      ),
    );
  }
}
