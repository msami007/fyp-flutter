import 'package:flutter/material.dart';

class ConnectDeviceScreen extends StatefulWidget {
  const ConnectDeviceScreen({super.key});

  @override
  State<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends State<ConnectDeviceScreen> {
  bool _isConnected = false;

  void connectEarbuds() {
    setState(() {
      _isConnected = !_isConnected;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_isConnected ? 'Earbuds Connected!' : 'Disconnected'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Earbuds')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isConnected ? Icons.headphones : Icons.headset_off,
              color: _isConnected ? Colors.green : Colors.grey,
              size: 100,
            ),
            const SizedBox(height: 20),
            Text(
              _isConnected ? 'Connected to Earbuds' : 'No Device Connected',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: connectEarbuds,
              child: Text(_isConnected ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
