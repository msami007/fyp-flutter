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
      backgroundColor: const Color(0xFF070B1D), // Darker background as in image
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
        : SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildAvatarSection(),
              const SizedBox(height: 40),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(Icons.person_outline_rounded, 'PERSONAL DETAILS'),
                    const SizedBox(height: 16),
                    _buildDetailsCard(),
                    
                    const SizedBox(height: 32),
                    _buildSectionHeader(Icons.hearing_outlined, 'HEARING STATUS'),
                    const SizedBox(height: 16),
                    _hearingProfile == null 
                      ? _buildEmptyHearingCard()
                      : _buildHearingStatusGrid(),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF6C63FF), width: 4),
              ),
              child: Center(
                child: Text(
                  (_fullName?.isNotEmpty == true) ? _fullName![0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Positioned(
              bottom: 5,
              right: 5,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF6C63FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          (_fullName ?? 'User Name').toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '@${_username ?? 'username'}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6C63FF), size: 18),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          _buildDetailRow(Icons.face_rounded, 'Full Name', _fullName ?? 'Not set'),
          const SizedBox(height: 24),
          _buildDetailRow(Icons.alternate_email_rounded, 'Username', _username ?? 'Not set'),
          const SizedBox(height: 24),
          _buildDetailRow(Icons.email_rounded, 'Email Address', _email ?? 'Not set'),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
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
                label,
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHearingStatusGrid() {
    final leftGain = _hearingProfile?['leftEarGain']?.toString() ?? '1.0';
    final rightGain = _hearingProfile?['rightEarGain']?.toString() ?? '1.0';

    return Row(
      children: [
        Expanded(child: _buildStatusCard('LEFT EAR', '${(double.parse(leftGain) * 100).toInt()}%')),
        const SizedBox(width: 16),
        Expanded(child: _buildStatusCard('RIGHT EAR', '${(double.parse(rightGain) * 100).toInt()}%')),
      ],
    );
  }

  Widget _buildStatusCard(String ear, String percentage) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Text(
            ear,
            style: const TextStyle(
              color: Color(0xFF6C63FF),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            percentage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Boost Level',
            style: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildEmptyHearingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.hearing_disabled_rounded, color: Colors.white.withOpacity(0.1), size: 48),
          const SizedBox(height: 16),
          const Text(
            'No Active Profile',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete a hearing test to see your results here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}
