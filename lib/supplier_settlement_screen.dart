import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SupplierSettlementScreen extends StatefulWidget {
  const SupplierSettlementScreen({super.key});

  @override
  State<SupplierSettlementScreen> createState() =>
      _SupplierSettlementScreenState();
}

class _SupplierSettlementScreenState extends State<SupplierSettlementScreen> {
  final Color darkGreen = const Color(0xFF1B5E20);

  String? selectedShop; // Cassia or Battistini

  List<Map<String, dynamic>> shortEatProducts = [];

  final Map<String, TextEditingController> morningControllers = {};
  final Map<String, TextEditingController> nightControllers = {};

  bool isLoading = false;

  @override
  void dispose() {
    morningControllers.forEach((_, controller) => controller.dispose());
    nightControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  // 🔍 Firestore වෙතින් Live Data කියවීම
  Future<void> _loadShortEatProducts() async {
    if (selectedShop == null) return;

    setState(() => isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('products_data')
          .where('is_short_eat', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> tempProducts = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        String productId = doc.id;

        double costPrice =
            double.tryParse(data['cost_price']?.toString() ?? "1.00") ?? 1.00;
        double shopPrice =
            double.tryParse(data['shop_price']?.toString() ?? "1.50") ?? 1.50;
        double profit =
            double.tryParse(data['profit']?.toString() ?? "0.50") ?? 0.50;

        String stockKey = selectedShop == "Cassia"
            ? "cassia_stock"
            : "battistini_stock";
        int currentStock = int.tryParse(data[stockKey]?.toString() ?? "0") ?? 0;

        tempProducts.add({
          'id': productId,
          'name': data['name'] ?? 'Unknown Short Eat',
          'cost_price': costPrice,
          'shop_price': shopPrice,
          'profit': profit,
          'current_stock': currentStock,
        });

        if (!morningControllers.containsKey(productId)) {
          morningControllers[productId] = TextEditingController();
        }
        if (!nightControllers.containsKey(productId)) {
          nightControllers[productId] = TextEditingController(text: "0");
        }
      }

      if (mounted) {
        setState(() {
          shortEatProducts = tempProducts;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Short Eats Load Error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ➕ අලුත් බඩු ප්‍රමාණය එකතු කර Firestore Update කරන Logic එක
  Future<void> _addStockToFirestore(String productId, int currentStock) async {
    int enteredVal =
        int.tryParse(morningControllers[productId]?.text ?? "0") ?? 0;
    if (enteredVal <= 0) return;

    setState(() => isLoading = true);

    int finalStock = currentStock + enteredVal;
    String stockKey = selectedShop == "Cassia"
        ? "cassia_stock"
        : "battistini_stock";

    try {
      await FirebaseFirestore.instance
          .collection('products_data')
          .doc(productId)
          .update({
            stockKey: finalStock,
            'last_updated': FieldValue.serverTimestamp(),
          });

      morningControllers[productId]?.clear();
      await _loadShortEatProducts(); // UI Refresh
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Stock Update Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  // ✏️ 🔥 වැරදුණු Stock එක කෙලින්ම Edit කරගන්නා Logic එක (Long Press)
  Future<void> _editStockDirectly(String productId, int currentStock) async {
    final editController = TextEditingController(text: currentStock.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Edit Stock Quantity",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter the correct total stock quantity for this item.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: editController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: darkGreen, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: darkGreen),
            onPressed: () async {
              int newStock = int.tryParse(editController.text) ?? 0;
              Navigator.pop(context);

              setState(() => isLoading = true);
              String stockKey = selectedShop == "Cassia"
                  ? "cassia_stock"
                  : "battistini_stock";

              try {
                await FirebaseFirestore.instance
                    .collection('products_data')
                    .doc(productId)
                    .update({
                      stockKey: newStock,
                      'last_updated': FieldValue.serverTimestamp(),
                    });
                await _loadShortEatProducts();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Update Error: $e"),
                    backgroundColor: Colors.red,
                  ),
                );
                setState(() => isLoading = false);
              }
            },
            child: const Text(
              "UPDATE STOCK",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _calculateValues() {
    setState(() {}); // 🔥 මේකෙන් Unsold ගහනකොට Live ගණන් වෙනස් වෙනවා
  }

  @override
  Widget build(BuildContext context) {
    int totalMorningStock = 0;
    double totalSupplierPayment = 0.0;
    double totalShopProfit = 0.0;

    for (var product in shortEatProducts) {
      String id = product['id'];
      double cost = product['cost_price'];
      double profit = product['profit'];

      int morning = product['current_stock'];
      int night = int.tryParse(nightControllers[id]?.text ?? "0") ?? 0;
      int sold = morning - night;
      if (sold < 0) sold = 0;

      totalMorningStock += morning;
      totalSupplierPayment += (sold * cost);
      totalShopProfit += (sold * profit);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text(
          "Settlement & Live Profit",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: darkGreen,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildCreativeHeader("Step 1: Select Shop Location 🏢"),
            _buildShopSelectorCard(),
            const SizedBox(height: 20),

            if (selectedShop == null)
              _buildEmptyPlaceholder("Please select a shop to continue")
            else if (isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 50),
                child: CircularProgressIndicator(),
              )
            else if (shortEatProducts.isEmpty)
              _buildEmptyPlaceholder("No Short Eats found in Firestore")
            else ...[
              _buildCreativeHeader(
                "Step 2: Cumulative Received Stock ($selectedShop) ☀️",
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  "💡 Hold press for 2 seconds to Edit incorrect stock.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              ...shortEatProducts.map((p) => _buildStockAddCard(p)),
              const SizedBox(height: 20),

              _buildSummaryCard(
                "Cumulative Total Stock On Hand",
                "$totalMorningStock Items",
                Colors.blue[800]!,
                Icons.inventory,
              ),
              const SizedBox(height: 25),

              _buildCreativeHeader(
                "Step 3: Enter Night Unsold Returns (Live Calc) 🌙",
              ),
              ...shortEatProducts.map((p) => _buildUnsoldInputCard(p)),
              const SizedBox(height: 25),

              _buildCreativeHeader("Step 4: Live Financial Summary 🧾"),
              _buildFinancialSummaryCard(totalSupplierPayment, totalShopProfit),
              const SizedBox(height: 30),

              _buildSaveButton(),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreativeHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 10, top: 5),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: darkGreen,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildShopSelectorCard() {
    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedShop,
            hint: const Text("Select Cassia or Battistini"),
            isExpanded: true,
            icon: Icon(
              Icons.arrow_circle_down_rounded,
              color: darkGreen,
              size: 28,
            ),
            items: const [
              DropdownMenuItem(value: "Cassia", child: Text("Cassia Branch")),
              DropdownMenuItem(
                value: "Battistini",
                child: Text("Battistini Branch"),
              ),
            ],
            onChanged: (val) {
              setState(() => selectedShop = val);
              _loadShortEatProducts();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStockAddCard(Map<String, dynamic> p) {
    String id = p['id'];
    int currentStock = p['current_stock'];

    return GestureDetector(
      onLongPress: () => _editStockDirectly(
        id,
        currentStock,
      ), // 🔥 තත්පර 2ක් Press කළ විට Edit වේ
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Current Total Qty: $currentStock",
                        style: TextStyle(
                          color: darkGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 70,
                    height: 40,
                    child: TextField(
                      controller: morningControllers[id],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: "+Add",
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.add_circle, color: darkGreen, size: 36),
                    onPressed: () => _addStockToFirestore(id, currentStock),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnsoldInputCard(Map<String, dynamic> p) {
    String id = p['id'];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                p['name'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              height: 42,
              child: TextField(
                controller: nightControllers[id],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (_) =>
                    _calculateValues(), // 🔥 Live update calculation
                decoration: InputDecoration(
                  hintText: "Unsold",
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialSummaryCard(double totalSupplier, double totalProfit) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          ...shortEatProducts.map((p) {
            String id = p['id'];
            double cost = p['cost_price'];
            int morning = p['current_stock'];
            int night = int.tryParse(nightControllers[id]?.text ?? "0") ?? 0;
            int sold = morning - night;
            if (sold < 0) sold = 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildSettleRow("Vended / Sold (Qty)", "$sold Items"),
                  _buildSettleRow(
                    "Cost Price (ea)",
                    "€${cost.toStringAsFixed(2)}",
                  ),
                  _buildSettleRow(
                    "Due Payout",
                    "€${(sold * cost).toStringAsFixed(2)}",
                  ),
                  const Divider(thickness: 1),
                ],
              ),
            );
          }),
          _buildSettleRow(
            "Total Supplier Payout",
            "€${totalSupplier.toStringAsFixed(2)}",
            isBold: true,
          ),
          const Divider(thickness: 1.5),
          _buildSettleRow(
            "Net Shop Profit",
            "€${totalProfit.toStringAsFixed(2)}",
            isBold: true,
            textStyle: TextStyle(
              color: darkGreen,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 40),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettleRow(
    String title,
    String value, {
    bool isBold = false,
    TextStyle? textStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          Text(
            value,
            style:
                textStyle ??
                TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                  color: isBold ? Colors.black : Colors.black87,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton.icon(
      onPressed: _saveDailyReportToHistory,
      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
      label: const Text(
        "FINALIZE & RESET DAILY DATA",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: darkGreen,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
      ),
    );
  }

  Widget _buildEmptyPlaceholder(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.hourglass_empty, size: 70, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDailyReportToHistory() async {
    if (selectedShop == null) return;

    setState(() => isLoading = true);
    String todayStr = DateTime.now().toString().substring(0, 10);

    Map<String, dynamic> reportData = {
      'shop': selectedShop,
      'date': todayStr,
      'timestamp': FieldValue.serverTimestamp(),
      'items': shortEatProducts.map((p) {
        String id = p['id'];
        int morning = p['current_stock'];
        int night = int.tryParse(nightControllers[id]?.text ?? "0") ?? 0;
        int sold = morning - night;
        if (sold < 0) sold = 0;

        return {
          'product_id': id,
          'name': p['name'],
          'morning_stock': morning,
          'night_return': night,
          'sold_qty': sold,
          'cost_price': p['cost_price'],
          'profit_per_item': p['profit'],
          'total_supplier_pay': sold * p['cost_price'],
          'total_profit': sold * p['profit'],
        };
      }).toList(),
    };

    try {
      await FirebaseFirestore.instance
          .collection('short_eats_settlements')
          .doc("${todayStr}_$selectedShop")
          .set(reportData, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Settlement for $selectedShop saved successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      for (var p in shortEatProducts) {
        nightControllers[p['id']]?.text = "0";
      }
      await _loadShortEatProducts();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }
}
