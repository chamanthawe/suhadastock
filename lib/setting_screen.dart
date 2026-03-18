import 'package:flutter/material.dart';
import 'printer_manager.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  final TextEditingController _ipController = TextEditingController();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedIP();
  }

  void _loadSavedIP() async {
    String? ip = await PrinterManager.getSavedIP();
    if (ip != null) {
      setState(() => _ipController.text = ip);
    }
  }

  void _handleConnect() async {
    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter printer IP")));
      return;
    }

    setState(() => _isConnecting = true);
    bool ok = await PrinterManager.connect(_ipController.text);

    if (!mounted) return;
    setState(() => _isConnecting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? "Connected to Munbyn Printer!" : "Connection Failed!",
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Printer Settings"),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: "Printer IP Address",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 7,
                  backgroundColor: PrinterManager.isConnected
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(PrinterManager.isConnected ? "Online" : "Offline"),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isConnecting ? null : _handleConnect,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                child: Text(
                  _isConnecting ? "Connecting..." : "Test Connection",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
