import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/HearingProfileService.dart';

class ProfileAccountScreen extends StatefulWidget {
  const ProfileAccountScreen({super.key});

  @override
  State<ProfileAccountScreen> createState() => _ProfileAccountScreenState();
}

class _ProfileAccountScreenState extends State<ProfileAccountScreen> {
  String? _userId;
  String? _fullName;
  String? _username;
  String? _email;
  Map<String, dynamic>? _hearingProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final profileService = HearingProfileService();
    
    _userId = prefs.getString('user_id');
    _username = prefs.getString('username');
    final token = prefs.getString('jwt_token');
    debugPrint('Profile: Loaded from prefs - userId: $_userId, token available: ${token != null}');
    
    // Attempt to fetch fresh data from server if userId is available
    if (_userId != null && _userId!.isNotEmpty && token != null) {
      try {
        final url = 'http://145.79.8.129:3000/api/admin/get-customer/$_userId';
        debugPrint('Profile: Fetching customer details from $url');
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        
        debugPrint('Profile: API Response - Status: ${response.statusCode}');
        debugPrint('Profile: API Response - Body: ${response.body}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          // The API returns the user object directly at the root
          _fullName = data['fullname'];
          _email = data['email'];
          debugPrint('Profile: Success - Name: $_fullName, Email: $_email');
          
          // Persist locally for next time
          if (_fullName != null) await prefs.setString('full_name', _fullName!);
          if (_email != null) await prefs.setString('email', _email!);
        } else if (response.statusCode == 401) {
          debugPrint('Profile: Token expired or invalid. 401 Unauthorized.');
          // Optional: Redirect to login if token is expired
        } else {
          debugPrint('Profile: API error fetching customer details (Status: ${response.statusCode})');
        }
      } catch (e) {
        debugPrint('Profile: Exception fetching customer details: $e');
      }
    }

    // Fallback to local data if server fetch failed or was skipped
    if (_fullName == null || _fullName!.isEmpty) {
      _fullName = prefs.getString('full_name');
      debugPrint('Profile: Falling back to local full_name: $_fullName');
    }
    if (_email == null || _email!.isEmpty) {
      _email = prefs.getString('email');
      debugPrint('Profile: Falling back to local email: $_email');
    }

    final hp = await profileService.getLocalProfile();
    
    setState(() {
      _hearingProfile = hp;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E2139),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF0A0E27),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
        : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Personal Information'),
              const SizedBox(height: 12),
              _buildInfoCard([
                _buildInfoRow(Icons.person_rounded, 'Full Name', _fullName ?? 'Not set'),
                _buildDivider(),
                _buildInfoRow(Icons.alternate_email_rounded, 'Username', _username ?? 'Not set'),
                _buildDivider(),
                _buildInfoRow(Icons.email_rounded, 'Email', _email ?? 'Not set'),
              ]),
              
              const SizedBox(height: 24),
              _buildSectionTitle('Hearing Profile'),
              const SizedBox(height: 12),
              _hearingProfile == null 
                ? _buildEmptyHearingCard()
                : _buildHearingProfileCard(),
              
              const SizedBox(height: 24),
              _buildSectionTitle('Account Security'),
              const SizedBox(height: 12),
              _buildInfoCard([
                _buildInfoRow(Icons.badge_rounded, 'User ID', _userId ?? 'Not available'),
              ]),
              
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'HearWise v1.0.0',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6C63FF), size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.white.withOpacity(0.05),
      height: 1,
      indent: 56,
    );
  }

  Widget _buildEmptyHearingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(Icons.hearing_disabled_rounded, color: Colors.white.withOpacity(0.2), size: 48),
          const SizedBox(height: 16),
          const Text(
            'No hearing profile found',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete a hearing test to see your results here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHearingProfileCard() {
    final leftGain = _hearingProfile?['leftEarGain']?.toString() ?? '1.0';
    final rightGain = _hearingProfile?['rightEarGain']?.toString() ?? '1.0';
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1E2139), const Color(0xFF1E2139).withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.hearing_rounded, 'Hearing Optimization', 'Active'),
          _buildDivider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildEarMetric('Left Ear', '${(double.parse(leftGain) * 100).toInt()}% boost'),
                Container(width: 1, height: 40, color: Colors.white.withOpacity(0.1)),
                _buildEarMetric('Right Ear', '${(double.parse(rightGain) * 100).toInt()}% boost'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarMetric(String ear, String value) {
    return Column(
      children: [
        Text(ear, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
