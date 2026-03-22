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
  List<String> syncLogs = []; // අලුත් Log ලිස්ට් එක
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
    if (isSyncing || pendingItems.isEmpty || baseUrl == null) return;

    isSyncing = true;
    syncStatus = "Syncing...";

    // Safety Delay: තත්පර 1-10 අතර random කාලයක්
    await Future.delayed(Duration(seconds: Random().nextInt(10) + 1));

    try {
      List<Map<String, dynamic>> toProcess = List.from(pendingItems);

      for (var data in toProcess) {
        final item = data['item'];
        final int soldQty = data['soldQty'];
        final String targetKey = data['targetKey'];

        final url =
            "$baseUrl/products/${item['id']}?consumer_key=$ck&consumer_secret=$cs";
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          var serverData = jsonDecode(response.body);
          int currentStock = serverData['stock_quantity'] ?? 0;
          int newStock = (currentStock - soldQty).clamp(0, 999999);

          final putResponse = await http.put(
            Uri.parse(url),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "stock_quantity": newStock,
              "meta_data": [
                {"key": targetKey, "value": newStock.toString()},
              ],
            }),
          );

          if (putResponse.statusCode == 200) {
            _addLog("Success: ${data['name']} (-$soldQty) -> New: $newStock");
            pendingItems.removeWhere((element) => element['id'] == data['id']);
            await _saveToDisk();
          }
        }
        await Future.delayed(const Duration(seconds: 1)); // සර්වර් එකට විවේකයක්
      }

      secondsRemaining = 600;
      syncStatus = "All Synced!";
    } catch (e) {
      _addLog("Error: Connection Failed");
      syncStatus = "Retry in progress...";
    } finally {
      isSyncing = false;
    }
  }

  void _addLog(String message) {
    String time = DateFormat('HH:mm:ss').format(DateTime.now());
    syncLogs.insert(0, "[$time] $message");
    if (syncLogs.length > 20) syncLogs.removeLast(); // උපරිම 20යි
  }

  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('time_sync_data', jsonEncode(pendingItems));
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('time_sync_data');
    if (data != null) {
      pendingItems = List<Map<String, dynamic>>.from(jsonDecode(data));
    }
  }
}
