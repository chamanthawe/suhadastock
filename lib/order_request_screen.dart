import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart'; // Firebase Realtime Database
import 'package:firebase_core/firebase_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'constants.dart';

class OrderRequestScreen extends StatefulWidget {
  final List allProducts;
  const OrderRequestScreen({super.key, required this.allProducts});

  @override
  State<OrderRequestScreen> createState() => _OrderRequestScreenState();
}

class _OrderRequestScreenState extends State<OrderRequestScreen> {
  // --- Theme Color ---
  final Color darkGreen = const Color(0xFF1B5E20);

  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://suhada-inventory-default-rtdb.europe-west1.firebasedatabase.app',
  ).ref("order_requests");

  List<Map<String, dynamic>> currentCart = [];
  List<Map<String, dynamic>> orderHistory = [];
  bool isSyncing = false;
  bool isSearching = false;
  List searchResults = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _listenToOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- පවතින Logic (අත නොතබන ලදී) ---

  void _listenToOrders() {
    _dbRef.onValue.listen((event) {
      final dynamic data = event.snapshot.value;
      if (data != null) {
        Map<dynamic, dynamic> values = Map<dynamic, dynamic>.from(data as Map);
        List<Map<String, dynamic>> tempHistory = [];
        values.forEach((key, value) {
          tempHistory.add(Map<String, dynamic>.from(value));
        });

        tempHistory.sort(
          (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0),
        );

        if (mounted) {
          setState(() {
            orderHistory = tempHistory;
          });
        }
      } else {
        if (mounted) {
          setState(() => orderHistory = []);
        }
      }
    });
  }

  Future<void> _submitToFirebase() async {
    if (currentCart.isEmpty) return;

    String orderId =
        "ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
    Map<String, dynamic> newOrder = {
      'id': orderId,
      'timestamp': ServerValue.timestamp,
      'date': DateTime.now().toString().substring(0, 16),
      'items': List.from(currentCart),
      'status': 'Pending',
    };

    try {
      await _dbRef.child(orderId).set(newOrder);
      await _showPdfPreview(newOrder['items'], orderId);

      if (!mounted) return;
      setState(() {
        currentCart.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Request Sent to Cloud Successfully!"),
          backgroundColor: darkGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Firebase Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _completeAndSyncStock(int index) async {
    if (isSyncing) return;
    setState(() => isSyncing = true);

    var order = orderHistory[index];
    String orderId = order['id'];

    try {
      for (var item in order['items']) {
        final url =
            "${AppConstants.baseUrl}/products/${item['id']}?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}";

        final response = await http.get(Uri.parse(url));
        final pData = json.decode(response.body);

        List meta = pData['meta_data'] ?? [];
        var bMeta = meta.firstWhere(
          (m) => m['key'] == 'battistini_stock',
          orElse: () => {'value': '0'},
        );

        int currentCS =
            int.tryParse(pData['stock_quantity']?.toString() ?? '0') ?? 0;
        int currentBS = int.tryParse(bMeta['value'].toString()) ?? 0;

        int finalCS = currentCS - (item['qty'] as int);
        int finalBS = currentBS + (item['qty'] as int);

        await http.put(
          Uri.parse(url),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            "stock_quantity": finalCS,
            "meta_data": [
              {"key": "battistini_stock", "value": finalBS.toString()},
            ],
          }),
        );
      }

      await _dbRef.child(orderId).update({'status': 'Completed'});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Stock Updated in WooCommerce!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Sync Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => isSyncing = false);
      }
    }
  }

  Future<void> _showPdfPreview(List items, String orderId) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text("SUHADA INVENTORY - ORDER REQUEST"),
              ),
              pw.SizedBox(height: 10),
              pw.Text("Order ID: $orderId"),
              pw.Text("Date: ${DateTime.now().toString().substring(0, 16)}"),
              pw.Divider(),
              pw.TableHelper.fromTextArray(
                headers: ['Product Name', 'Quantity'],
                data: items
                    .map((item) => [item['name'], item['qty'].toString()])
                    .toList(),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 20),
                child: pw.Text("Status: PENDING DELIVERY"),
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text(
            "Stock Request System",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: darkGreen,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            indicatorColor: Colors.yellow,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: "CREATE NEW", icon: Icon(Icons.add_shopping_cart)),
              Tab(text: "CLOUD HISTORY", icon: Icon(Icons.cloud_done)),
            ],
          ),
        ),
        body: TabBarView(
          children: [_buildNewRequestTab(), _buildCloudHistoryTab()],
        ),
      ),
    );
  }

  Widget _buildNewRequestTab() {
    return Column(
      children: [
        _buildSearchHeader(),
        Expanded(
          child: Stack(
            children: [
              if (currentCart.isEmpty && !isSearching)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 80,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Cart is empty",
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ListView.builder(
                padding: const EdgeInsets.only(top: 10, bottom: 80),
                itemCount: currentCart.length,
                itemBuilder: (context, index) {
                  final item = currentCart[index];
                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      title: Text(
                        item['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Quantity: ${item['qty']}",
                        style: TextStyle(
                          color: darkGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: CircleAvatar(
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => currentCart.removeAt(index)),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (isSearching)
                Center(child: CircularProgressIndicator(color: darkGreen)),
              if (searchResults.isNotEmpty) _buildSearchOverlay(),
            ],
          ),
        ),
        if (currentCart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _submitToFirebase,
              icon: const Icon(
                Icons.cloud_upload_outlined,
                color: Colors.white,
              ),
              label: const Text(
                "SUBMIT REQUEST & PRINT",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: darkGreen,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCloudHistoryTab() {
    if (orderHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            const Text(
              "No Cloud Records Found",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: orderHistory.length,
      itemBuilder: (context, index) {
        final order = orderHistory[index];
        bool isPending = order['status'] == 'Pending';
        Color statusColor = isPending
            ? Colors.orange[800]!
            : Colors.green[700]!;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: statusColor.withValues(alpha: 0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: ExpansionTile(
            leading: Icon(
              isPending ? Icons.hourglass_top_rounded : Icons.verified_rounded,
              color: statusColor,
            ),
            title: Text(
              "Order: ${order['id']}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              "${order['date']} • ${order['status']}",
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
            children: [
              const Divider(height: 1),
              ...order['items']
                  .map<Widget>(
                    (item) => ListTile(
                      dense: true,
                      title: Text(
                        item['name'],
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: Text(
                        "x${item['qty']}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                  .toList(),
              if (isPending)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: isSyncing
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: darkGreen,
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () => _completeAndSyncStock(index),
                                icon: const Icon(Icons.sync_alt, size: 18),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[600],
                                  foregroundColor: Colors.white,
                                ),
                                label: const Text("Complete & Sync"),
                              ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () => _dbRef.child(order['id']).remove(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[50],
                          foregroundColor: Colors.red,
                          elevation: 0,
                        ),
                        child: const Text("Cancel"),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkGreen,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _searchProductsOnline,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          hintText: "Search Product Name...",
          prefixIcon: Icon(Icons.search, color: darkGreen),
          suffixIcon: IconButton(
            icon: Icon(Icons.qr_code_scanner, color: darkGreen),
            onPressed: _openScanner,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          fillColor: Colors.white,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Container(
      color: Colors.white,
      child: ListView.separated(
        itemCount: searchResults.length,
        separatorBuilder: (c, i) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final p = searchResults[index];
          return ListTile(
            leading: Icon(
              Icons.inventory_2,
              color: darkGreen.withValues(alpha: 0.5),
            ),
            title: Text(
              p['name'],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              "Current Stock: ${p['stock_quantity'] ?? 0}",
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Icon(Icons.add_circle, color: darkGreen),
            onTap: () => _showQuantityDialog(p),
          );
        },
      ),
    );
  }

  void _showQuantityDialog(dynamic p) {
    final qtyController = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          p['name'],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter quantity to request from Battistini branch.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "Quantity",
                labelStyle: TextStyle(color: darkGreen),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: darkGreen, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text("CANCEL", style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                currentCart.add({
                  'id': p['id'],
                  'name': p['name'],
                  'qty': int.tryParse(qtyController.text) ?? 0,
                  'sku': p['sku'] ?? '',
                });
                searchResults = [];
                _searchController.clear();
              });
              Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: darkGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "ADD TO LIST",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 15),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "Scan Product Barcode",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(25),
                ),
                child: MobileScanner(
                  onDetect: (capture) async {
                    final String barcodeValue =
                        capture.barcodes.first.rawValue ?? "";
                    if (barcodeValue.isNotEmpty) {
                      if (context.mounted) Navigator.pop(context);
                      _scanAndAddProduct(barcodeValue);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanAndAddProduct(String code) async {
    setState(() => isSearching = true);
    try {
      final url =
          "${AppConstants.baseUrl}/products?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}&sku=$code";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        List data = json.decode(response.body);
        if (data.isNotEmpty) {
          if (!mounted) return;
          _showQuantityDialog(data.first);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Product not found!")));
        }
      }
    } finally {
      if (mounted) setState(() => isSearching = false);
    }
  }

  Future<void> _searchProductsOnline(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    setState(() => isSearching = true);
    try {
      final url =
          "${AppConstants.baseUrl}/products?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}&search=$query";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() => searchResults = json.decode(response.body));
      }
    } finally {
      if (mounted) setState(() => isSearching = false);
    }
  }
}
