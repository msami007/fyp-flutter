import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HearingProfileService {
  static const String baseUrl = "http://145.79.8.129:3000/api/hearing-profile"; // ✅ note: use http if no SSL

  /// Fetch user's hearing profile from server
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final res = await http.get(Uri.parse("$baseUrl/$userId"));
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      await saveLocalProfile(data); // ✅ changed here
      return data;
    } else {
      return null; // Not found
    }
  }

  /// Create a new hearing profile for a user
  Future<void> createProfile(String userId, Map<String, dynamic> profile) async {
    final body = {...profile, "userId": userId};
    final res = await http.post(
      Uri.parse(baseUrl),
      headers: {"Content-Type": "application/json"},
      body: json.encode(body),
    );
    if (res.statusCode == 201) await saveLocalProfile(json.decode(res.body)); // ✅
  }

  /// Update an existing hearing profile
  Future<void> updateProfile(String userId, Map<String, dynamic> profile) async {
    final res = await http.put(
      Uri.parse("$baseUrl/$userId"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(profile),
    );
    if (res.statusCode == 200) await saveLocalProfile(json.decode(res.body)); // ✅
  }

  /// ✅ Public method to save profile locally
  Future<void> saveLocalProfile(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("hearing_profile", json.encode(profile));
  }

  /// ✅ Get hearing profile from local storage
  Future<Map<String, dynamic>?> getLocalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString("hearing_profile");
    return data != null ? json.decode(data) : null;
  }
}
