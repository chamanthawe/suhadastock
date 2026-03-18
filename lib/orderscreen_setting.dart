import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class OrderScreenSetting extends StatefulWidget {
  final bool isRefreshing;
  final VoidCallback onRefreshStock;
  final String baseUrl, ck, cs, selectedShop;

  // --- Static Variables (App එක පුරාම data share කරගන්න) ---
  static int pendingOrderCount = 0;
  static List<Map<String, dynamic>> pendingItemsForSync = [];
  static Timer? autoSyncTimer;
  static int secondsRemaining = 600;

  // --- Static Methods (Order Screen එකේ සිට call කළ හැකි methods) ---

  // 1. Pending count එක වැඩි කිරීමට (Error එක ආපු තැනට විසඳුම මෙන්න)
  static void incrementOrderCount() {
    pendingOrderCount++;
  }

  // 2. අලුත් order එකක් පෝලිමට එකතු කිරීමට
  static Future<void> addOrderToPending(
    Map<String, dynamic> item,
    int soldQty, // විකුණපු ප්‍රමාණය
    String targetKey,
  ) async {
    pendingItemsForSync.add({
      'item': item,
      'soldQty': soldQty,
      'targetKey': targetKey,
      'id': item['id'].toString(),
    });
    pendingOrderCount = pendingItemsForSync.length;
    await savePendingToDisk();
  }

  static Future<void> savePendingToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pending_orders_sync',
      jsonEncode(pendingItemsForSync),
    );
  }

  static Future<void> loadPendingFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedData = prefs.getString('pending_orders_sync');
    if (storedData != null) {
      pendingItemsForSync = List<Map<String, dynamic>>.from(
        jsonDecode(storedData),
      );
      pendingOrderCount = pendingItemsForSync.length;
    }
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
  bool _isSyncingNow = false;
  String _syncStatus = "System Ready";

  @override
  void initState() {
    super.initState();
    _initAppLogic();
  }

  Future<void> _initAppLogic() async {
    await OrderScreenSetting.loadPendingFromDisk();
    if (mounted) setState(() {});
    _startTimer();
  }

  void _startTimer() {
    OrderScreenSetting.autoSyncTimer?.cancel();
    OrderScreenSetting.autoSyncTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) return;
        setState(() {
          if (OrderScreenSetting.secondsRemaining > 0) {
            OrderScreenSetting.secondsRemaining--;
          } else {
            _triggerBatchSync();
          }
          // Orders 10ක් පිරුණු ගමන් auto sync වෙනවා
          if (OrderScreenSetting.pendingOrderCount >= 10) {
            _triggerBatchSync();
          }
        });
      },
    );
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  // --- වැදගත්ම කොටස: Safe Atomic Sync Logic ---
  Future<void> _triggerBatchSync() async {
    if (_isSyncingNow || OrderScreenSetting.pendingItemsForSync.isEmpty) return;

    bool online = await _hasInternet();
    if (!online) {
      setState(() => _syncStatus = "Offline: Waiting for Internet...");
      return;
    }

    setState(() {
      _isSyncingNow = true;
      _syncStatus = "Syncing (Checking Server Stock)...";
    });

    try {
      // List එකේ copy එකක් අරන් process කරනවා
      List<Map<String, dynamic>> itemsToProcess = List.from(
        OrderScreenSetting.pendingItemsForSync,
      );

      for (var data in itemsToProcess) {
        final item = data['item'];
        final int soldQty = data['soldQty'] ?? 1;
        final String targetKey = data['targetKey'];
        bool isBat = widget.selectedShop.toLowerCase().contains("battistini");

        // 1. GET Request: සර්වර් එකේ දැනට තියෙන හරියටම stock එක බලනවා
        final getUrl =
            "${widget.baseUrl}/products/${item['id']}?consumer_key=${widget.ck}&consumer_secret=${widget.cs}";
        final getResponse = await http.get(Uri.parse(getUrl));

        if (getResponse.statusCode == 200) {
          var serverData = jsonDecode(getResponse.body);
          int currentServerStock = serverData['stock_quantity'] ?? 0;

          // 2. සර්වර් එකේ අගයෙන් විකුණපු ගාන අඩු කරනවා (Safe Calculation)
          int updatedStock = currentServerStock - soldQty;
          if (updatedStock < 0) updatedStock = 0;

          // 3. PUT Request: අලුත් අගය සර්වර් එකට යවනවා
          final putResponse = await http
              .put(
                Uri.parse(getUrl),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  if (!isBat) "stock_quantity": updatedStock,
                  "meta_data": [
                    {"key": targetKey, "value": updatedStock.toString()},
                  ],
                }),
              )
              .timeout(const Duration(seconds: 15));

          if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
            // සාර්ථක නම් විතරක් පෝලිමෙන් අයින් කරනවා
            OrderScreenSetting.pendingItemsForSync.remove(data);
            await OrderScreenSetting.savePendingToDisk();
          }
        }
      }

      setState(() {
        OrderScreenSetting.pendingOrderCount =
            OrderScreenSetting.pendingItemsForSync.length;
        if (OrderScreenSetting.pendingItemsForSync.isEmpty) {
          OrderScreenSetting.secondsRemaining = 600;
          _syncStatus = "All Synced Safely!";
        }
      });
    } catch (e) {
      setState(() => _syncStatus = "Sync Failed. Retrying later.");
    } finally {
      if (mounted) setState(() => _isSyncingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _buildStatusCard(),
            const SizedBox(height: 20),
            ListTile(
              tileColor: Colors.blue[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.refresh, color: Colors.blue),
              title: const Text("Refresh Firestore Stock"),
              trailing: widget.isRefreshing
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.chevron_right),
              onTap: widget.onRefreshStock,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
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
              "OFFLINE SYNC MANAGER (SAFE MODE)",
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            _infoRow(
              "Pending Updates",
              "${OrderScreenSetting.pendingOrderCount}",
              Colors.orangeAccent,
            ),
            const SizedBox(height: 10),
            _infoRow(
              "Auto-Sync In",
              "${(OrderScreenSetting.secondsRemaining / 60).floor()}m ${OrderScreenSetting.secondsRemaining % 60}s",
              Colors.greenAccent,
            ),
            const SizedBox(height: 20),
            Text(
              "System Status: $_syncStatus",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 15),
            _isSyncingNow
                ? const CircularProgressIndicator(color: Colors.orangeAccent)
                : ElevatedButton.icon(
                    onPressed: OrderScreenSetting.pendingItemsForSync.isEmpty
                        ? null
                        : _triggerBatchSync,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("SYNC DATA MANUALLY"),
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
