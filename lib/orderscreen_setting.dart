import 'dart:async';

import 'package:flutter/material.dart';

import 'time_sync.dart';

class OrderScreenSetting extends StatefulWidget {
  final bool isRefreshing;
  final VoidCallback onRefreshStock;
  final String baseUrl, ck, cs, selectedShop;

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
    // Timer එක දිගටම ක්‍රියාත්මකයි - මෙය logs සහ countdown සඳහා අත්‍යවශ්‍ය වේ.
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
    double syncProgress = (syncProvider.pendingItems.length / 20).clamp(
      0.0,
      1.0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text(
          "System Control Center",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Hardware Monitor Section එක වෙනුවට සරල Header එකක් (RAM/CPU අයින් කළා)
          _buildSimpleMonitorHeader(),

          // 2. Status Card (Pending & Batches)
          _buildStatusCard(syncProvider, syncProgress),

          // 3. Log Section
          Expanded(child: _buildLogSection(syncProvider)),
        ],
      ),
    );
  }

  // RAM සහ CPU Check කරන කොටස ඉවත් කර සාදා නිම කළ Header එක
  Widget _buildSimpleMonitorHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "ENGINE STATUS:",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: TimeSync().isSyncing ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 5),
              Text(
                TimeSync().isSyncing ? "SYNCING DATA..." : "ENGINE STANDBY",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: TimeSync().isSyncing ? Colors.orange : Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(TimeSync syncProvider, double progress) {
    return Container(
      margin: const EdgeInsets.all(15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "BATCH QUEUE MONITOR",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              if (syncProvider.isSyncing)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 15),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(5),
            color: Colors.blueGrey[800],
            backgroundColor: Colors.grey[100],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoTile("Pending", "${syncProvider.pendingItems.length}"),
              _infoTile("Synced Today", "${syncProvider.todaySyncBatchCount}"),
              _infoTile(
                "Next Cycle",
                "${(syncProvider.secondsRemaining / 60).floor()}m ${syncProvider.secondsRemaining % 60}s",
              ),
            ],
          ),
          const Divider(height: 30),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: syncProvider.pendingItems.isEmpty
                  ? null
                  : () => syncProvider.triggerSync(),
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: const Text("EXECUTE FORCE SYNC"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[900],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String title, String val) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          val,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildLogSection(TimeSync syncProvider) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 25, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "ENGINE TRAFFIC LOGS",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blueGrey,
                    letterSpacing: 1.2,
                  ),
                ),
                if (syncProvider.syncLogs.isNotEmpty)
                  const Icon(Icons.terminal, size: 14, color: Colors.blueGrey),
              ],
            ),
          ),
          Expanded(
            child: syncProvider.syncLogs.isEmpty
                ? const Center(
                    child: Text(
                      "No traffic logs detected",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 25,
                      vertical: 5,
                    ),
                    itemCount: syncProvider.syncLogs.length,
                    itemBuilder: (context, i) {
                      final log = syncProvider.syncLogs[i];
                      bool isError =
                          log.contains("Fail") || log.contains("Error");
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey[50]!,
                              width: 1,
                            ),
                          ),
                        ),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isError ? Colors.red : Colors.blueGrey[600],
                            height: 1.4,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
