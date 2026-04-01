import 'dart:async';
import 'dart:convert';

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

  // --- අලුත් Variables ---
  int todaySyncBatchCount = 0; // අද දින සාර්ථක වූ බැච් ගණන
  String? lastSyncDate; // අවසන් වරට Sync වූ දිනය (Reset කිරීමට)

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
    _checkAndResetDailyCount(); // දවස අලුත් නම් Counter එක 0 කරයි
    _startTimer();
  }

  void _checkAndResetDailyCount() {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (lastSyncDate != today) {
      todaySyncBatchCount = 0;
      lastSyncDate = today;
      _saveToDisk();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (secondsRemaining > 0)
        secondsRemaining--;
      else
        triggerSync();

      if (pendingItems.length >= 20 && !isSyncing) triggerSync();
    });
  }

  Future<void> addOrder(
    Map<String, dynamic> item,
    int qty,
    String targetKey,
  ) async {
    int index = pendingItems.indexWhere(
      (element) => element['id'] == item['id'].toString(),
    );
    if (index != -1) {
      pendingItems[index]['soldQty'] += qty;
    } else {
      pendingItems.add({
        'id': item['id'].toString(),
        'name': item['name'],
        'soldQty': qty,
        'targetKey': targetKey,
      });
    }
    await _saveToDisk();
  }

  Future<void> triggerSync() async {
    if (isSyncing || pendingItems.isEmpty || baseUrl == null) {
      if (pendingItems.isEmpty) syncStatus = "Ready";
      return;
    }

    _checkAndResetDailyCount();
    isSyncing = true;
    syncStatus = "Batch Syncing...";
    secondsRemaining = 600;

    List<Map<String, dynamic>> allToProcess = List.from(pendingItems);

    try {
      int chunkSize = 20;

      for (var i = 0; i < allToProcess.length; i += chunkSize) {
        final stopwatch = Stopwatch()..start();
        int end = (i + chunkSize < allToProcess.length)
            ? i + chunkSize
            : allToProcess.length;
        List<Map<String, dynamic>> currentChunk = allToProcess.sublist(i, end);

        _addLog(
          "Starting Batch: ${i ~/ chunkSize + 1} (${currentChunk.length} items)",
        );
        List<Map<String, dynamic>> updatePayload = [];
        List<String> successfulIdsInThisBatch = [];

        for (var data in currentChunk) {
          try {
            final getUrl =
                "$baseUrl/products/${data['id']}?consumer_key=$ck&consumer_secret=$cs";
            final response = await http
                .get(Uri.parse(getUrl))
                .timeout(const Duration(seconds: 15));

            if (response.statusCode == 200) {
              var serverData = jsonDecode(response.body);
              int currentServerStock = serverData['stock_quantity'] ?? 0;
              int finalStock = (currentServerStock - data['soldQty'])
                  .clamp(0, 999999)
                  .toInt();

              updatePayload.add({
                "id": int.parse(data['id']),
                "stock_quantity": finalStock,
                "meta_data": [
                  {"key": data['targetKey'], "value": finalStock.toString()},
                ],
              });
              successfulIdsInThisBatch.add(data['id']);
            }
          } catch (e) {
            _addLog("Fetch Error: ${data['name']} - Will retry");
          }
        }

        if (updatePayload.isNotEmpty) {
          final batchUrl =
              "$baseUrl/products/batch?consumer_key=$ck&consumer_secret=$cs";
          final putResponse = await http
              .post(
                Uri.parse(batchUrl),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"update": updatePayload}),
              )
              .timeout(const Duration(seconds: 30));

          stopwatch.stop();

          if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
            todaySyncBatchCount++; // බැච් එක සාර්ථකයි
            _addLog(
              "Batch Success (${stopwatch.elapsedMilliseconds}ms) - Count: $todaySyncBatchCount",
            );

            // සාර්ථක වූ අයිටම් පමණක් ලිස්ට් එකෙන් ඉවත් කරයි
            pendingItems.removeWhere(
              (item) => successfulIdsInThisBatch.contains(item['id']),
            );
            await _saveToDisk();
          } else {
            _addLog("Server Error in Batch - Keeping items in list");
          }
        }

        if (end < allToProcess.length) {
          _addLog("Cooldown (3s)...");
          await Future.delayed(const Duration(seconds: 3));
        }
      }

      syncStatus = pendingItems.isEmpty ? "Done" : "Partial (Items remaining)";
    } catch (e) {
      _addLog("Network Error - Pending retry");
      syncStatus = "Pending Retry";
    } finally {
      isSyncing = false;
    }
  }

  void _addLog(String message) {
    String time = DateFormat('HH:mm:ss').format(DateTime.now());
    syncLogs.insert(0, "[$time] $message");
    if (syncLogs.length > 30) syncLogs.removeLast();
  }

  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('time_sync_data', jsonEncode(pendingItems));
    await prefs.setInt('today_sync_batch_count', todaySyncBatchCount);
    await prefs.setString('last_sync_date', lastSyncDate ?? "");
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('time_sync_data');
    todaySyncBatchCount = prefs.getInt('today_sync_batch_count') ?? 0;
    lastSyncDate = prefs.getString('last_sync_date');

    if (data != null) {
      try {
        pendingItems = List<Map<String, dynamic>>.from(jsonDecode(data));
      } catch (e) {
        pendingItems = [];
      }
    }
  }
}
