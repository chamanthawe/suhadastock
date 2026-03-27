import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimeSync {
  static final TimeSync _instance = TimeSync._internal();
  factory TimeSync() => _instance;
  TimeSync._internal();

  Timer? _timer;
  int secondsRemaining = 600;
  List<Map<String, dynamic>> pendingItems = [];
  List<String> syncLogs = [];
  bool isSyncing = false;
  String syncStatus = "Ready";

  String? baseUrl, ck, cs, selectedShop;

  Future<void> init({
    required String url,
    required String key,
    required String secret,
    required String shop,
  }) async {
    baseUrl = url;
    ck = key;
    cs = secret;
    selectedShop = shop;
    await _loadFromDisk();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (secondsRemaining > 0) {
        secondsRemaining--;
      } else {
        triggerSync();
      }
      // කස්ටමර්ලා වැඩි නිසා බඩු 10ක් පිරුණු ගමන් Sync එක පටන් ගන්නවා
      if (pendingItems.length >= 10) triggerSync();
    });
  }

  Future<void> addOrder(
    Map<String, dynamic> item,
    int qty,
    String targetKey,
  ) async {
    pendingItems.add({
      'item': item,
      'soldQty': qty,
      'targetKey': targetKey,
      'id': item['id'].toString(),
      'name': item['name'],
    });
    await _saveToDisk();
  }

  Future<void> triggerSync() async {
    secondsRemaining = 600;

    if (isSyncing || pendingItems.isEmpty || baseUrl == null) {
      if (pendingItems.isEmpty) syncStatus = "Ready";
      return;
    }

    isSyncing = true;
    syncStatus = "Smart Syncing...";

    // කඩවල් දෙක අතර Request එක බෙදීමට (Shop A: 5-10s, Shop B: 15-25s)
    int initialWait =
        (selectedShop?.toLowerCase().contains("battistini") ?? false)
        ? 15 + Random().nextInt(10)
        : 5 + Random().nextInt(5);
    await Future.delayed(Duration(seconds: initialWait));

    try {
      List<Map<String, dynamic>> toProcess = List.from(pendingItems);
      int counter = 0;

      for (var data in toProcess) {
        counter++;
        final item = data['item'];
        final int soldQty = data['soldQty'];
        final String targetKey = data['targetKey'];
        final url =
            "$baseUrl/products/${item['id']}?consumer_key=$ck&consumer_secret=$cs";

        final stopwatch = Stopwatch()..start();

        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          var serverData = jsonDecode(response.body);
          int currentStock = serverData['stock_quantity'] ?? 0;
          int newStock = (currentStock - soldQty).clamp(0, 999999);

          final putResponse = await http
              .put(
                Uri.parse(url),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "stock_quantity": newStock,
                  "meta_data": [
                    {"key": targetKey, "value": newStock.toString()},
                  ],
                }),
              )
              .timeout(const Duration(seconds: 20));

          stopwatch.stop();

          if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
            _addLog(
              "Sync: ${data['name']} (${stopwatch.elapsedMilliseconds}ms)",
            );
            pendingItems.removeWhere((element) => element['id'] == data['id']);
            await _saveToDisk();
          }
        }

        // --- සර්වර් එකට විවේකයක් (සෑම භාණ්ඩයක් අතරම තත්පර 5ක්) ---
        await Future.delayed(const Duration(seconds: 5));

        // --- භාණ්ඩ 5ක් අවසන් වූ විට තත්පර 10ක Cool-down එකක් ---
        if (counter % 5 == 0 && counter < toProcess.length) {
          _addLog("Server cooling down... (10s)");
          await Future.delayed(const Duration(seconds: 10));
        }
      }

      syncStatus = pendingItems.isEmpty ? "Done" : "Partial";
    } catch (e) {
      _addLog("Network Busy - Retrying later");
    } finally {
      isSyncing = false;
    }
  }

  void _addLog(String message) {
    String time = DateFormat('HH:mm:ss').format(DateTime.now());
    syncLogs.insert(0, "[$time] $message");
    if (syncLogs.length > 20) syncLogs.removeLast();
  }

  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('time_sync_data', jsonEncode(pendingItems));
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('time_sync_data');
    if (data != null) {
      try {
        pendingItems = List<Map<String, dynamic>>.from(jsonDecode(data));
      } catch (e) {
        pendingItems = [];
      }
    }
  }
}
