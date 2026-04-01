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
    // තත්පරයෙන් තත්පරය UI එක Update කරන්නේ Countdown එක සහ Logs පෙනීමටයි
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

    // නව Batch සීමාව 20 බැවින් ප්‍රගතිය 20 ට අනුව ගණනය කෙරේ
    double progress = (syncProvider.pendingItems.length / 20).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text(
          "System Control Center",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueGrey[900]!, const Color(0xFFF4F7F9)],
            stops: const [0.15, 0.15],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: [
              _buildModernStatusCard(syncProvider, progress),
              const SizedBox(height: 20),
              _buildFirestoreTile(),
              const SizedBox(height: 20),
              _buildLogSection(syncProvider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernStatusCard(TimeSync syncProvider, double progress) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "BATCH QUEUE MONITOR",
                    style: TextStyle(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Text(
                    "Auto-sync: 10 items | Max Batch: 20 | Shop: ${widget.selectedShop}",
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
              Icon(
                syncProvider.isSyncing ? Icons.sync : Icons.bolt_rounded,
                color: syncProvider.isSyncing
                    ? Colors.orange
                    : Colors.blueGrey[800],
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 25),

          // Progress Bar
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 14,
                    width: constraints.maxWidth,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    height: 14,
                    width: constraints.maxWidth * progress,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: progress >= 1.0
                            ? [Colors.red, Colors.orangeAccent]
                            : [Colors.blue, Colors.lightBlueAccent],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. දැනට පෝලිමේ තියෙන Orders ගණන
              _infoColumn(
                "Pending",
                "${syncProvider.pendingItems.length}",
                syncProvider.pendingItems.length > 15
                    ? Colors.red
                    : Colors.blue[900]!,
              ),
              // 2. අද දින සාර්ථකව නිම කළ Batch ගණන (20 බැගින් වූ)
              _infoColumn(
                "Synced Today",
                "${syncProvider.todaySyncBatchCount}",
                Colors.green[700]!,
              ),
              // 3. ඊළඟ Sync එකට තියෙන කාලය
              _infoColumn(
                "Next Cycle",
                "${(syncProvider.secondsRemaining / 60).floor()}m ${syncProvider.secondsRemaining % 60}s",
                Colors.blueGrey[800]!,
              ),
            ],
          ),
          const Divider(height: 40, thickness: 0.5),

          syncProvider.isSyncing
              ? Column(
                  children: [
                    const LinearProgressIndicator(color: Colors.orange),
                    const SizedBox(height: 12),
                    Text(
                      syncProvider.syncStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: syncProvider.pendingItems.isEmpty
                        ? null
                        : () => syncProvider.triggerSync(),
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: const Text("FORCE BATCH SYNC"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[900],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _infoColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildFirestoreTile() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10),
        ],
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE3F2FD),
          child: Icon(Icons.cloud_download, color: Colors.blue),
        ),
        title: const Text(
          "Firebase Direct Refresh",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        trailing: widget.isRefreshing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: widget.onRefreshStock,
      ),
    );
  }

  Widget _buildLogSection(TimeSync syncProvider) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 12),
            child: Text(
              "SERVER TRAFFIC & BATCH LOGS",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: syncProvider.syncLogs.isEmpty
                  ? const Center(
                      child: Text(
                        "No sync logs available",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: syncProvider.syncLogs.length,
                      separatorBuilder: (c, i) =>
                          const Divider(height: 15, color: Color(0xFFF5F5F5)),
                      itemBuilder: (context, index) {
                        String log = syncProvider.syncLogs[index];
                        bool isError =
                            log.contains("Error") || log.contains("Fail");
                        bool isSuccess = log.contains("Success");

                        return Row(
                          children: [
                            Icon(
                              isError
                                  ? Icons.error_outline
                                  : (isSuccess
                                        ? Icons.check_circle_outline
                                        : Icons.info_outline),
                              size: 14,
                              color: isError
                                  ? Colors.red
                                  : (isSuccess ? Colors.green : Colors.blue),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: isError
                                      ? Colors.red[800]
                                      : Colors.blueGrey[700],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
