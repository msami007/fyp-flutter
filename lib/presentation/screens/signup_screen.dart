import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants/app_colors.dart';
import '../../routes/app_routes.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> signup() async {
    final fullname = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty || fullname.isEmpty) return;

    setState(() => _loading = true);
    final customer = {
      'fullname': fullname,
      'username': username,
      'password': password,
      'email': email,
      'companyntn' : "1234568-7"
    };

    try {
      final response = await http.post(
        Uri.parse('http://145.79.8.129:3000/api/admin/add-customer'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'customer': customer}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Account created!')));
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(data['message'] ?? 'Signup failed')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Create Account', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: AppColors.primary),
                onPressed: signup,
                child: const Text('Sign Up', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }
}
