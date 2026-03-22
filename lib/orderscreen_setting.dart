import 'dart:async';

import 'package:flutter/material.dart';

import 'time_sync.dart';

class OrderScreenSetting extends StatefulWidget {
  final bool isRefreshing;
  final VoidCallback onRefreshStock;
  final String baseUrl, ck, cs, selectedShop;

  static Future<void> addOrderToPending(
    Map<String, dynamic> item,
    int soldQty,
    String targetKey,
  ) async {
    await TimeSync().addOrder(item, soldQty, targetKey);
  }

  const OrderScreenSetting({
    super.key,
    required this.isRefreshing,
    required this.onRefreshStock,
    required this.baseUrl,
    required this.ck,
    required this.cs,
    required this.selectedShop,
  });

  @override
  State<OrderScreenSetting> createState() => _OrderScreenSettingState();
}

class _OrderScreenSettingState extends State<OrderScreenSetting> {
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = TimeSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text("POS System Control"),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatusCard(syncProvider),
            const SizedBox(height: 20),
            ListTile(
              tileColor: Colors.blue[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.refresh, color: Colors.blue),
              title: const Text("Refresh Firestore Stock"),
              subtitle: const Text("Manual sync with Firebase"),
              trailing: widget.isRefreshing
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.chevron_right),
              onTap: widget.onRefreshStock,
            ),
            const SizedBox(height: 20),
            const Text(
              "RECENT SYNC LOGS",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: syncProvider.syncLogs.isEmpty
                    ? const Center(
                        child: Text(
                          "No logs yet",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: syncProvider.syncLogs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              syncProvider.syncLogs[index],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(TimeSync syncProvider) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.blueGrey[800]!, Colors.blueGrey[700]!],
          ),
        ),
        child: Column(
          children: [
            const Text(
              "OFFLINE SYNC MANAGER",
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Colors.white24),
            _infoRow(
              "Pending Updates",
              "${syncProvider.pendingItems.length}",
              Colors.orangeAccent,
            ),
            const SizedBox(height: 10),
            _infoRow(
              "Auto-Sync In",
              "${(syncProvider.secondsRemaining / 60).floor()}m ${syncProvider.secondsRemaining % 60}s",
              Colors.greenAccent,
            ),
            const SizedBox(height: 15),
            Text(
              "Status: ${syncProvider.syncStatus}",
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 15),
            syncProvider.isSyncing
                ? const CircularProgressIndicator(color: Colors.orangeAccent)
                : ElevatedButton.icon(
                    onPressed: syncProvider.pendingItems.isEmpty
                        ? null
                        : () => syncProvider.triggerSync(),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("SYNC NOW"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, Color valColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        Text(
          value,
          style: TextStyle(
            color: valColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
