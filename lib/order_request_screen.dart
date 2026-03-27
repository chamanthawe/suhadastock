import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore (For Live product stock)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart'; // Realtime DB (For Order tracking)
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 For saving cart state

import 'constants.dart';

class OrderRequestScreen extends StatefulWidget {
  final List allProducts;
  const OrderRequestScreen({super.key, required this.allProducts});

  @override
  State<OrderRequestScreen> createState() => _OrderRequestScreenState();
}

class _OrderRequestScreenState extends State<OrderRequestScreen> {
  final Color darkGreen = const Color(0xFF1B5E20);

  // Realtime Database reference for orders
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
    _loadSavedCart(); // 🔥 Load cart when screen starts
    _listenToOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 🔥 💾 Cart එක Save කරන Function එක
  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedCart = json.encode(currentCart);
    await prefs.setString('saved_order_cart', encodedCart);
  }

  // 🔥 📂 Save උන Cart එක Load කරන Function එක
  Future<void> _loadSavedCart() async {
    final prefs = await SharedPreferences.getInstance();
    String? encodedCart = prefs.getString('saved_order_cart');
    if (encodedCart != null && encodedCart.isNotEmpty) {
      setState(() {
        currentCart = List<Map<String, dynamic>>.from(json.decode(encodedCart));
      });
    }
  }

  // 🔥 🗑️ Cart එක සම්පූර්ණයෙන්ම Clear කරන Function එක
  Future<void> _clearCart() async {
    setState(() {
      currentCart.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_order_cart');
  }

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

  // 🔥 1. ඉල්ලීම Cloud එකට යැවීම
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

      await _clearCart(); // Clear cart from memory and SharedPreferences

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

  // 🔥 2. Cassia එකෙන් බඩු ලැබුණාම Battistini එකෙන් Confirm කිරීම සහ Stock Sync කිරීම
  Future<void> _completeAndSyncStock(int index) async {
    if (isSyncing) return;
    setState(() => isSyncing = true);

    var order = orderHistory[index];
    String orderId = order['id'];

    try {
      for (var item in order['items']) {
        String productId = item['id'].toString();
        double requestedQty = double.tryParse(item['qty'].toString()) ?? 0.0;

        if (requestedQty <= 0) continue;

        // 🟢 2.1 Firestore එකෙන් දැනට තියෙන Live Stock කියවීම
        final docRef = FirebaseFirestore.instance
            .collection('products_data')
            .doc(productId);
        final docSnap = await docRef.get();

        if (!docSnap.exists) continue;

        final data = docSnap.data()!;
        double currentCassia =
            double.tryParse(data['cassia_stock']?.toString() ?? '0') ?? 0.0;
        double currentBattistini =
            double.tryParse(data['battistini_stock']?.toString() ?? '0') ?? 0.0;

        // 🟢 2.2 ගණනය කිරීම (Cassia අඩු වෙනවා, Battistini වැඩි වෙනවා)
        double finalCassia = currentCassia - requestedQty;
        double finalBattistini = currentBattistini + requestedQty;

        // 🟢 2.3 WooCommerce යාවත්කාලීන කිරීම
        final wooUrl =
            "${AppConstants.baseUrl}/products/$productId?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}";

        await http.put(
          Uri.parse(wooUrl),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            "stock_quantity": finalCassia
                .toInt(), // WooCommerce Main Stock (Cassia)
            "meta_data": [
              {"key": "battistini_stock", "value": finalBattistini.toString()},
              {"key": "cassia_stock", "value": finalCassia.toString()},
            ],
          }),
        );

        // 🟢 2.4 Firestore Live Stock යාවත්කාලීන කිරීම
        await docRef.update({
          'cassia_stock': finalCassia,
          'battistini_stock': finalBattistini,
          'last_updated': FieldValue.serverTimestamp(),
        });
      }

      await _dbRef.child(orderId).update({'status': 'Completed'});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Stock Successfully Transferred from Cassia to Battistini!",
          ),
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
                child: pw.Text("SUHADA INVENTORY - STOCK TRANSFER"),
              ),
              pw.SizedBox(height: 10),
              pw.Text("Order ID: $orderId"),
              pw.Text("Date: ${DateTime.now().toString().substring(0, 16)}"),
              pw.Divider(),
              pw.TableHelper.fromTextArray(
                headers: ['Product Name', 'Quantity (Qty/Kg)'],
                data: items
                    .map((item) => [item['name'], item['qty'].toString()])
                    .toList(),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 20),
                child: pw.Text(
                  "Origin: CASSIA BRANCH | Destination: BATTISTINI BRANCH",
                ),
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
        // 🔥 කුඩා Clear Cart Button එක පෙන්වන Section එක
        if (currentCart.isNotEmpty && !isSearching)
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _clearCart,
                icon: const Icon(
                  Icons.delete_sweep,
                  color: Colors.red,
                  size: 18,
                ),
                label: const Text(
                  "Clear All Items",
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  backgroundColor: Colors.red.withOpacity(0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
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
                        "No items in request",
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ListView.builder(
                padding: const EdgeInsets.only(top: 5, bottom: 80),
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
                        "Req Qty/Kg: ${item['qty']}",
                        style: TextStyle(
                          color: darkGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: CircleAvatar(
                        backgroundColor: Colors.red.withOpacity(0.1),
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () async {
                            setState(() {
                              currentCart.removeAt(index);
                            });
                            await _saveCart(); // 🔥 Save cart after single item removal
                          },
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
            decoration: const BoxDecoration(
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
              "No Requests Found",
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
            side: BorderSide(color: statusColor.withOpacity(0.3), width: 1),
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
                        "x ${item['qty']}",
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
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[600],
                                  foregroundColor: Colors.white,
                                ),
                                label: const Text("Receive & Update Stock"),
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
        onChanged: _searchProductsOnline, // 🔥 Live Firestore Search
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          hintText: "Search in Cassia Stock...",
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
            leading: Icon(Icons.inventory_2, color: darkGreen.withOpacity(0.5)),
            title: Text(
              p['name'],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              "Cassia Stock: ${p['cassia_stock'] ?? 0}", // 🔥 Cassia වල තියෙන Live Stock එක පෙන්වයි
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Icon(Icons.add_circle, color: darkGreen),
            onTap: () {
              // 🔥 🛑 Cassia stock එක බින්දුවට වඩා වැඩිනම් පමණක් Dialog එක Open කරයි.
              double cassiaStock =
                  double.tryParse(p['cassia_stock'].toString()) ?? 0.0;
              if (cassiaStock <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Out of Stock in Cassia Branch! Can't request.",
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              } else {
                _showQuantityDialog(p);
              }
            },
          );
        },
      ),
    );
  }

  void _showQuantityDialog(dynamic p) {
    final qtyController = TextEditingController();
    bool isLoose = p['is_loose'] == true;

    // 🔥 දැනට තියෙන Live Stock එක ලබාගැනීම
    double availableStock =
        double.tryParse(p['cassia_stock']?.toString() ?? '0') ?? 0.0;

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
            Text(
              isLoose
                  ? "Enter Weight in Kg (Ex: 1.5)"
                  : "Enter Quantity to request from Cassia Stock.",
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 5),
            Text(
              "Available Stock: $availableStock",
              style: const TextStyle(
                fontSize: 14,
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: qtyController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: isLoose ? "Weight (Kg)" : "Quantity",
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
            onPressed: () async {
              double requestedQty = double.tryParse(qtyController.text) ?? 0.0;

              if (requestedQty <= 0) {
                return; // 🛑 0 ට වඩා අඩු අගයන් block කිරීම
              }

              // 🔥 🛑 තියෙන Stock එකට වඩා වැඩියෙන් Request කරොත් Block කරන තැන
              if (requestedQty > availableStock) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Not enough stock in Cassia! Max available is $availableStock",
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return; // Dialog එකේ නවතියි, Cart එකට වැටෙන්නේ නෑ
              }

              setState(() {
                currentCart.add({
                  'id': p['id'],
                  'name': p['name'],
                  'qty': requestedQty,
                  'sku': p['sku'] ?? '',
                });
                searchResults = [];
                _searchController.clear();
              });

              await _saveCart(); // 🔥 Save cart immediately after adding an item

              if (mounted) Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: darkGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "ADD TO REQUEST",
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

  // Barcode එකෙන් සර්ච් කරද්දීත් Firestore එක පාවිච්චි කිරීම
  Future<void> _scanAndAddProduct(String code) async {
    setState(() => isSearching = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('products_data')
          .where('sku', isEqualTo: code)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        if (!mounted) return;

        double cassiaStock =
            double.tryParse(data['cassia_stock']?.toString() ?? '0') ?? 0.0;

        if (cassiaStock <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Out of Stock in Cassia Branch! Can't request by Scan.",
              ),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          _showQuantityDialog({
            'id': doc.id,
            'name': data['name'],
            'sku': data['sku'],
            'cassia_stock': cassiaStock,
            'is_loose': data['is_loose'] ?? false,
          });
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Product SKU not found in Cloud Database!"),
          ),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print("Scanner Error: $e");
    } finally {
      if (mounted) setState(() => isSearching = false);
    }
  }

  // 🔥 3. කෙලින්ම Firestore එකෙන් Live Search කිරීම
  Future<void> _searchProductsOnline(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => isSearching = true);

    try {
      final String searchLower = query.toLowerCase();

      final snapshot = await FirebaseFirestore.instance
          .collection('products_data')
          .get();

      List<Map<String, dynamic>> results = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String name = data['name']?.toString().toLowerCase() ?? '';
        final String sku = data['sku']?.toString() ?? '';

        if (name.contains(searchLower) || sku.contains(searchLower)) {
          results.add({
            'id': doc.id,
            'name': data['name'],
            'sku': sku,
            'cassia_stock': data['cassia_stock'] ?? 0,
            'battistini_stock': data['battistini_stock'] ?? 0,
            'is_loose': data['is_loose'] ?? false,
          });
        }
      }

      if (!mounted) return;
      setState(() => searchResults = results);
    } catch (e) {
      // ignore: avoid_print
      print("Firestore Search Error: $e");
    } finally {
      if (mounted) setState(() => isSearching = false);
    }
  }
}
