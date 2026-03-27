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
    // නව Smart Sync සීමාව 10 බැවින් ප්‍රගතිය 10 ට ගණනය කෙරේ
    double progress = (syncProvider.pendingItems.length / 10).clamp(0.0, 1.0);

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
                    "SMART QUEUE",
                    style: TextStyle(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Text(
                    "Auto-sync at 10 items | ID: ${widget.selectedShop}",
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
              Icon(
                syncProvider.isSyncing
                    ? Icons.sync_problem
                    : Icons.bolt_rounded,
                color: syncProvider.isSyncing
                    ? Colors.orange
                    : Colors.blueGrey[800],
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 25),

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
                      boxShadow: [
                        if (progress > 0)
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 6,
                          ),
                      ],
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
              _infoColumn(
                "Pending Items",
                "${syncProvider.pendingItems.length}/10",
                Colors.blue[900]!,
              ),
              _infoColumn(
                "Next Heartbeat",
                "${(syncProvider.secondsRemaining / 60).floor()}m ${syncProvider.secondsRemaining % 60}s",
                Colors.blueGrey[800]!,
              ),
            ],
          ),
          const Divider(height: 40, thickness: 0.5),

          syncProvider.isSyncing
              ? Column(
                  children: [
                    const LinearProgressIndicator(
                      color: Colors.orange,
                      backgroundColor: Color(0xFFEEEEEE),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      syncProvider.syncStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
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
                    label: const Text(
                      "MANUAL SMART SYNC",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[900],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
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
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE3F2FD),
          child: Icon(Icons.cloud_download, color: Colors.blue),
        ),
        title: const Text(
          "Firebase Direct Refresh",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: const Text(
          "Sync manual stock adjustments",
          style: TextStyle(fontSize: 11),
        ),
        trailing: widget.isRefreshing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
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
              "REAL-TIME SERVER LATENCY (Smart Monitor)",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                letterSpacing: 1,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: syncProvider.syncLogs.isEmpty
                  ? const Center(
                      child: Text(
                        "Waiting for first transaction...",
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
                            log.contains("Error") || log.contains("Failed");
                        bool isCooling = log.contains("cooling");

                        Color speedColor = Colors.green;
                        if (log.contains("ms")) {
                          int ms =
                              int.tryParse(
                                RegExp(r'(\d+)ms').firstMatch(log)?.group(1) ??
                                    '0',
                              ) ??
                              0;
                          if (ms > 1500)
                            speedColor = Colors.red; // 1.5s වඩා වැඩි නම් රතු
                          else if (ms > 800)
                            speedColor =
                                Colors.orange; // 800ms වඩා වැඩි නම් තැඹිලි
                        }

                        return Row(
                          children: [
                            Icon(
                              isCooling
                                  ? Icons.ac_unit_rounded
                                  : (isError ? Icons.error : Icons.circle),
                              size: isCooling ? 16 : 10,
                              color: isCooling
                                  ? Colors.blue
                                  : (isError ? Colors.red : speedColor),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: isCooling
                                      ? Colors.blue[700]
                                      : (isError
                                            ? Colors.red[800]
                                            : Colors.blueGrey[700]),
                                  fontWeight: isCooling
                                      ? FontWeight.bold
                                      : FontWeight.w500,
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
