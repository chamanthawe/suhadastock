import 'package:flutter/material.dart';

class OfflineOverlayWidget extends StatelessWidget {
  final bool isChecking;
  final VoidCallback onRetry;
  final Color primaryColor;

  const OfflineOverlayWidget({
    super.key,
    required this.isChecking,
    required this.onRetry,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          child: Container(
            padding: const EdgeInsets.all(40),
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 80,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 20),
                const Text(
                  "No Internet Connection",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                const Text(
                  "කරුණාකර අන්තර්ජාලය පරීක්ෂා කරන්න.\nData Sync කිරීමට අන්තර්ජාලය අත්‍යවශ්‍ය වේ.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey, fontSize: 14),
                ),
                const SizedBox(height: 30),
                isChecking
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text("RETRY CONNECTION"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
