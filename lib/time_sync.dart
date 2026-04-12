import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'; // compute සඳහා
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimeSync extends ChangeNotifier {
  static final TimeSync _instance = TimeSync._internal();
  factory TimeSync() => _instance;
  TimeSync._internal();

  Timer? _timer;
  // UI එකට විතරක් ඇහෙන විදිහට මේකNotifier එකක් කළා
  final ValueNotifier<int> timerNotifier = ValueNotifier<int>(600);

  int get secondsRemaining => timerNotifier.value;
  List<Map<String, dynamic>> pendingItems = [];
  List<String> syncLogs = [];
  bool isSyncing = false;
  String syncStatus = "Ready";
  int todaySyncBatchCount = 0;
  String? lastSyncDate;
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
    _checkAndResetDailyCount();
    _startTimer();
  }

  void _checkAndResetDailyCount() {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (lastSyncDate != today) {
      todaySyncBatchCount = 0;
      lastSyncDate = today;
      _saveToDisk();
      notifyListeners();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timerNotifier.value > 0) {
        timerNotifier.value--;
      } else {
        triggerSync();
      }
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
    notifyListeners();
  }

  Future<void> triggerSync() async {
    if (isSyncing || pendingItems.isEmpty || baseUrl == null) return;

    isSyncing = true;
    syncStatus = "Batch Syncing...";
    notifyListeners();
    timerNotifier.value = 600;

    try {
      int chunkSize = 20;
      List<Map<String, dynamic>> allToProcess = List.from(pendingItems);

      for (var i = 0; i < allToProcess.length; i += chunkSize) {
        int end = (i + chunkSize < allToProcess.length)
            ? i + chunkSize
            : allToProcess.length;
        List<Map<String, dynamic>> currentChunk = allToProcess.sublist(i, end);

        List<Map<String, dynamic>> updatePayload = [];
        List<String> successfulIds = [];

        for (var data in currentChunk) {
          try {
            final response = await http
                .get(
                  Uri.parse(
                    "$baseUrl/products/${data['id']}?consumer_key=$ck&consumer_secret=$cs",
                  ),
                )
                .timeout(const Duration(seconds: 10));

            if (response.statusCode == 200) {
              // පරණ iPad එකේ thread එක හිර නොවෙන්න compute පාවිච්චි කිරීම
              var serverData =
                  await compute(jsonDecode, response.body)
                      as Map<String, dynamic>;
              int currentStock = serverData['stock_quantity'] ?? 0;
              int finalStock = (currentStock - data['soldQty'])
                  .clamp(0, 999999)
                  .toInt();

              updatePayload.add({
                "id": int.parse(data['id']),
                "stock_quantity": finalStock,
                "meta_data": [
                  {"key": data['targetKey'], "value": finalStock.toString()},
                ],
              });
              successfulIds.add(data['id']);
            }
          } catch (e) {
            _addLog("Fetch Error: ${data['name']}");
          }
        }

        if (updatePayload.isNotEmpty) {
          final putResponse = await http
              .post(
                Uri.parse(
                  "$baseUrl/products/batch?consumer_key=$ck&consumer_secret=$cs",
                ),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"update": updatePayload}),
              )
              .timeout(const Duration(seconds: 20));

          if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
            todaySyncBatchCount++;
            pendingItems.removeWhere(
              (item) => successfulIds.contains(item['id']),
            );
            _addLog("Batch Success - Count: $todaySyncBatchCount");
            await _saveToDisk();
          }
        }
        if (end < allToProcess.length)
          await Future.delayed(const Duration(seconds: 3));
      }
      syncStatus = pendingItems.isEmpty ? "Done" : "Partial";
    } catch (e) {
      syncStatus = "Network Error";
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  void _addLog(String message) {
    syncLogs.insert(
      0,
      "[${DateFormat('HH:mm:ss').format(DateTime.now())}] $message",
    );
    if (syncLogs.length > 20) syncLogs.removeLast();
    notifyListeners();
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
    if (data != null)
      pendingItems = List<Map<String, dynamic>>.from(jsonDecode(data));
    notifyListeners();
  }
}
