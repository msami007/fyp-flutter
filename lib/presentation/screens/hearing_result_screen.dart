import 'package:flutter/material.dart';

class HearingResultScreen extends StatelessWidget {
  final Map<String, dynamic> profile;
  const HearingResultScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Hearing Profile Created")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Profile Summary:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Text("Left Ear Gain: ${profile['leftEarGain'].toStringAsFixed(2)}"),
            Text("Right Ear Gain: ${profile['rightEarGain'].toStringAsFixed(2)}"),
            const SizedBox(height: 20),
            const Text("Frequency Map:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: profile["frequencyMap"].entries.map<Widget>((e) {
                  return Text("${e.key}: ${e.value.toStringAsFixed(2)}");
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Done"),
            )
          ],
        ),
      ),
    );
  }
}
