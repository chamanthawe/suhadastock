import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SupplierSettlementScreen extends StatefulWidget {
  const SupplierSettlementScreen({super.key});

  @override
  State<SupplierSettlementScreen> createState() =>
      _SupplierSettlementScreenState();
}

class _SupplierSettlementScreenState extends State<SupplierSettlementScreen> {
  final Color darkGreen = const Color(0xFF1B5E20);
  final Color lightGreen = const Color(0xFFE8F5E9);

  String? selectedShop;
  List<Map<String, dynamic>> shortEatProducts = [];
  final Map<String, Map<String, TextEditingController>> morningControllers = {};
  final Map<String, Map<String, TextEditingController>> nightControllers = {};

  bool isLoading = false;

  @override
  void dispose() {
    morningControllers.forEach((_, map) => map.forEach((__, c) => c.dispose()));
    nightControllers.forEach((_, map) => map.forEach((__, c) => c.dispose()));
    super.dispose();
  }

  int _parseStock(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Future<void> _loadShortEatProducts() async {
    if (selectedShop == null) return;
    setState(() => isLoading = true);
    try {
      // මෙතනදි is_short_eat: true තියෙන products පමණක් query කරනවා
      final snapshot = await FirebaseFirestore.instance
          .collection('products_data')
          .where('is_short_eat', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> tempProducts = [];
      String shopPrefix = selectedShop!.toLowerCase();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        String productId = doc.id;

        tempProducts.add({
          'id': productId,
          'name': data['name'] ?? 'Unknown',
          'cost_price': _toDouble(data['cost_price']),
          'profit': _toDouble(data['profit']),
          'in_D': _parseStock(data['${shopPrefix}_in_D']),
          'in_P': _parseStock(data['${shopPrefix}_in_P']),
          'in_U': _parseStock(data['${shopPrefix}_in_U']),
          'in_B': _parseStock(data['${shopPrefix}_in_B']),
          'morning_stock': _parseStock(
            data[selectedShop == "Cassia"
                ? "cassia_morning_stock"
                : "battistini_morning_stock"],
          ),
          'live_stock': _parseStock(data['${shopPrefix}_stock']),
        });

        if (!morningControllers.containsKey(productId)) {
          morningControllers[productId] = {
            'D': TextEditingController(),
            'P': TextEditingController(),
            'U': TextEditingController(),
            'B': TextEditingController(),
          };
        }

        if (!nightControllers.containsKey(productId)) {
          nightControllers[productId] = {
            'D': TextEditingController(
              text: _parseStock(data['${shopPrefix}_out_D']).toString(),
            ),
            'P': TextEditingController(
              text: _parseStock(data['${shopPrefix}_out_P']).toString(),
            ),
            'U': TextEditingController(
              text: _parseStock(data['${shopPrefix}_out_U']).toString(),
            ),
            'B': TextEditingController(
              text: _parseStock(data['${shopPrefix}_out_B']).toString(),
            ),
          };
        }
      }
      setState(() {
        shortEatProducts = tempProducts;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // --- History එක Save කරන function එක ---
  Future<void> _saveToHistory(
    String productId,
    String productName,
    String supplier,
    int qty,
  ) async {
    if (qty <= 0) return;
    await FirebaseFirestore.instance.collection('suppliers_stock_history').add({
      'product_id': productId,
      'product_name': productName,
      'supplier': supplier,
      'quantity': qty,
      'shop': selectedShop,
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _addMorningStockOnly(
    String productId,
    String name,
    int curMorning,
    int curD,
    int curP,
    int curU,
    int curB,
  ) async {
    final c = morningControllers[productId]!;
    int iD = int.tryParse(c['D']!.text) ?? 0;
    int iP = int.tryParse(c['P']!.text) ?? 0;
    int iU = int.tryParse(c['U']!.text) ?? 0;
    int iB = int.tryParse(c['B']!.text) ?? 0;
    int totalNew = iD + iP + iU + iB;
    if (totalNew <= 0) return;

    setState(() => isLoading = true);
    String shopPrefix = selectedShop!.toLowerCase();

    try {
      if (iD > 0) await _saveToHistory(productId, name, 'D', iD);
      if (iP > 0) await _saveToHistory(productId, name, 'P', iP);
      if (iU > 0) await _saveToHistory(productId, name, 'U', iU);
      if (iB > 0) await _saveToHistory(productId, name, 'B', iB);

      await FirebaseFirestore.instance
          .collection('products_data')
          .doc(productId)
          .update({
            selectedShop == "Cassia"
                    ? "cassia_morning_stock"
                    : "battistini_morning_stock":
                curMorning + totalNew,
            '${shopPrefix}_in_D': curD + iD,
            '${shopPrefix}_in_P': curP + iP,
            '${shopPrefix}_in_U': iU + curU,
            '${shopPrefix}_in_B': curB + iB,
            '${shopPrefix}_stock': FieldValue.increment(totalNew),
          });
      c.forEach((_, ctrl) => ctrl.clear());
      await _loadShortEatProducts();
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _finalizeAndSaveEverything() async {
    if (selectedShop == null) return;
    setState(() => isLoading = true);

    String shopPrefix = selectedShop!.toLowerCase();
    String dateId = DateFormat('yyyy-MM-dd').format(DateTime.now());

    Map<String, Map<String, dynamic>> settlementData = {
      'D': {
        'morning_in': 0,
        'unsold_out': 0,
        'sold_qty': 0,
        'payout': 0.0,
        'profit': 0.0,
      },
      'P': {
        'morning_in': 0,
        'unsold_out': 0,
        'sold_qty': 0,
        'payout': 0.0,
        'profit': 0.0,
      },
      'U': {
        'morning_in': 0,
        'unsold_out': 0,
        'sold_qty': 0,
        'payout': 0.0,
        'profit': 0.0,
      },
      'B': {
        'morning_in': 0,
        'unsold_out': 0,
        'sold_qty': 0,
        'payout': 0.0,
        'profit': 0.0,
      },
    };

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (var p in shortEatProducts) {
        final c = nightControllers[p['id']]!;
        double cost = _toDouble(p['cost_price']);
        double profPerItem = _toDouble(p['profit']);

        int inD = _parseStock(p['in_D']);
        int outD = int.tryParse(c['D']!.text) ?? 0;
        int soldD = (inD - outD).clamp(0, 9999);
        double payoutD = 0.0;

        if (inD > 0) {
          int mandatoryPay = inD >= 15 ? 15 : inD;
          payoutD += mandatoryPay * cost;
          if (inD > 15) {
            int bufferItems = (inD > 20 ? 20 : inD) - 15;
            for (int i = 1; i <= bufferItems; i++) {
              if ((15 + i) <= soldD)
                payoutD += cost;
              else
                payoutD += 0.50;
            }
          }
          if (inD > 20 && soldD > 20) payoutD += (soldD - 20) * cost;
        }

        settlementData['D']!['morning_in'] += inD;
        settlementData['D']!['unsold_out'] += outD;
        settlementData['D']!['sold_qty'] += soldD;
        settlementData['D']!['payout'] += payoutD;
        settlementData['D']!['profit'] += (soldD * profPerItem);

        for (var code in ['P', 'U', 'B']) {
          int inQty = _parseStock(p['in_$code']);
          int outQty = int.tryParse(c[code]!.text) ?? 0;
          int sold = (inQty - outQty).clamp(0, 9999);
          settlementData[code]!['morning_in'] += inQty;
          settlementData[code]!['unsold_out'] += outQty;
          settlementData[code]!['sold_qty'] += sold;
          settlementData[code]!['payout'] += (sold * cost);
          settlementData[code]!['profit'] += (sold * profPerItem);
        }

        batch.update(
          FirebaseFirestore.instance.collection('products_data').doc(p['id']),
          {
            '${shopPrefix}_in_D': 0,
            '${shopPrefix}_in_P': 0,
            '${shopPrefix}_in_U': 0,
            '${shopPrefix}_in_B': 0,
            '${shopPrefix}_out_D': 0,
            '${shopPrefix}_out_P': 0,
            '${shopPrefix}_out_U': 0,
            '${shopPrefix}_out_B': 0,
            'cassia_morning_stock': 0,
            'battistini_morning_stock': 0,
            '${shopPrefix}_stock': 0,
          },
        );
      }

      for (var entry in settlementData.entries) {
        if (entry.value['morning_in'] > 0 || entry.value['unsold_out'] > 0) {
          batch.set(
            FirebaseFirestore.instance
                .collection('suppliers_settlements')
                .doc("${dateId}_${selectedShop}_${entry.key}"),
            {
              'date': dateId,
              'shop': selectedShop,
              'supplier': entry.key,
              ...entry.value,
              'timestamp': FieldValue.serverTimestamp(),
            },
          );
        }
      }
      await batch.commit();

      morningControllers.forEach((_, map) => map.forEach((__, c) => c.clear()));
      nightControllers.forEach((_, map) => map.forEach((__, c) => c.clear()));

      await _loadShortEatProducts();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Settlement Successful and Data Reset!")),
      );
    } catch (e) {
      setState(() => isLoading = false);
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalD = 0, totalP = 0, totalU = 0, totalB = 0, totalProfit = 0;
    int totalMorning = 0;

    for (var p in shortEatProducts) {
      totalMorning += _parseStock(p['morning_stock']);
      double cost = _toDouble(p['cost_price']);
      double prof = _toDouble(p['profit']);

      int inD = _parseStock(p['in_D']);
      int outD =
          int.tryParse(nightControllers[p['id']]?['D']?.text ?? "0") ?? 0;
      int soldD = (inD - outD).clamp(0, 999);

      if (inD > 0) {
        totalD += (inD >= 15 ? 15 : inD) * cost;
        if (inD > 15) {
          int buffer = (inD > 20 ? 20 : inD) - 15;
          for (int i = 1; i <= buffer; i++) {
            if ((15 + i) <= soldD)
              totalD += cost;
            else
              totalD += 0.50;
          }
        }
        if (inD > 20 && soldD > 20) totalD += (soldD - 20) * cost;
      }

      int soldP =
          (_parseStock(p['in_P']) -
                  (int.tryParse(nightControllers[p['id']]?['P']?.text ?? "0") ??
                      0))
              .clamp(0, 999);
      int soldU =
          (_parseStock(p['in_U']) -
                  (int.tryParse(nightControllers[p['id']]?['U']?.text ?? "0") ??
                      0))
              .clamp(0, 999);
      int soldB =
          (_parseStock(p['in_B']) -
                  (int.tryParse(nightControllers[p['id']]?['B']?.text ?? "0") ??
                      0))
              .clamp(0, 999);

      totalP += soldP * cost;
      totalU += soldU * cost;
      totalB += soldB * cost;
      totalProfit += (soldD + soldP + soldU + soldB) * prof;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text("Supplier Settlement"),
        backgroundColor: darkGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: selectedShop == null
          ? _buildInitialShopSelect()
          : isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildShopSelectorWidget(),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    "Step 1: Morning Stock (Long Press to Edit)",
                  ),
                  ...shortEatProducts.map(
                    (p) => GestureDetector(
                      onLongPress: () => _showEditMorningDialog(p),
                      child: _buildMorningCard(p),
                    ),
                  ),
                  _buildSummaryRow(
                    "Total Morning Stock",
                    "$totalMorning Items",
                    Colors.indigo,
                  ),
                  const SizedBox(height: 25),
                  _buildSectionHeader(
                    "Step 2: Evening Unsold Returns (D P U B)",
                  ),
                  ...shortEatProducts.map((p) => _buildNightCard(p)),
                  const SizedBox(height: 25),
                  _buildSectionHeader("Step 3: Financial Settlement"),
                  _buildFinancialCard(
                    totalD,
                    totalP,
                    totalU,
                    totalB,
                    totalProfit,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _finalizeAndSaveEverything,
                    child: const Text(
                      "FINALIZE & RESET ALL TO 0",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // UI Helpers (No deletions or changes to UI structure)
  Widget _buildMorningCard(Map<String, dynamic> p) {
    final c = morningControllers[p['id']]!;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            title: Text(
              p['name'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "Live Stock: ${p['live_stock']}",
              style: const TextStyle(
                color: Colors.blueGrey,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Text(
              "Total In: ${p['morning_stock']}",
              style: TextStyle(color: darkGreen, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _buildSmallInput(c['D']!, "D"),
                _buildSmallInput(c['P']!, "P"),
                _buildSmallInput(c['U']!, "U"),
                _buildSmallInput(c['B']!, "B"),
                IconButton(
                  onPressed: () => _addMorningStockOnly(
                    p['id'],
                    p['name'],
                    p['morning_stock'],
                    p['in_D'],
                    p['in_P'],
                    p['in_U'],
                    p['in_B'],
                  ),
                  icon: const Icon(Icons.add_circle, color: Colors.blue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNightCard(Map<String, dynamic> p) {
    final c = nightControllers[p['id']]!;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(p['name'])),
            _buildSmallInput(c['D']!, "D"),
            _buildSmallInput(c['P']!, "P"),
            _buildSmallInput(c['U']!, "U"),
            _buildSmallInput(c['B']!, "B"),
            IconButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('products_data')
                    .doc(p['id'])
                    .update({
                      '${selectedShop!.toLowerCase()}_out_D':
                          int.tryParse(c['D']!.text) ?? 0,
                      '${selectedShop!.toLowerCase()}_out_P':
                          int.tryParse(c['P']!.text) ?? 0,
                      '${selectedShop!.toLowerCase()}_out_U':
                          int.tryParse(c['U']!.text) ?? 0,
                      '${selectedShop!.toLowerCase()}_out_B':
                          int.tryParse(c['B']!.text) ?? 0,
                    });
                _loadShortEatProducts();
              },
              icon: const Icon(Icons.check_circle, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallInput(TextEditingController ctrl, String l) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: l,
          contentPadding: EdgeInsets.zero,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    ),
  );

  Widget _buildFinancialCard(
    double d,
    double p,
    double u,
    double b,
    double prof,
  ) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      children: [
        _finRow("D Supplier", d, Colors.blue),
        _finRow("P Supplier", p, Colors.purple),
        _finRow("U Supplier", u, Colors.teal),
        _finRow("B Supplier", b, Colors.red),
        const Divider(),
        _finRow("Total Profit", prof, darkGreen, isBold: true),
      ],
    ),
  );

  Widget _finRow(String t, double v, Color c, {bool isBold = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(t),
      Text(
        "€${v.toStringAsFixed(2)}",
        style: TextStyle(
          color: c,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    ],
  );

  Widget _buildSectionHeader(String t) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        t,
        style: TextStyle(color: darkGreen, fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget _buildSummaryRow(String t, String v, Color c) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(t, style: const TextStyle(color: Colors.white)),
        Text(
          v,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _buildInitialShopSelect() => Center(child: _buildShopSelectorWidget());

  Widget _buildShopSelectorWidget() => Container(
    width: 200,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isExpanded: true,
        hint: const Text("Select Shop"),
        value: selectedShop,
        items: [
          "Cassia",
          "Battistini",
        ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (v) {
          setState(() => selectedShop = v);
          _loadShortEatProducts();
        },
      ),
    ),
  );

  void _showEditMorningDialog(Map<String, dynamic> p) {
    final dC = TextEditingController(text: p['in_D'].toString());
    final pC = TextEditingController(text: p['in_P'].toString());
    final uC = TextEditingController(text: p['in_U'].toString());
    final bC = TextEditingController(text: p['in_B'].toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit: ${p['name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildSmallInput(dC, "D")),
                Expanded(child: _buildSmallInput(pC, "P")),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildSmallInput(uC, "U")),
                Expanded(child: _buildSmallInput(bC, "B")),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              int nD = int.tryParse(dC.text) ?? 0;
              int nP = int.tryParse(pC.text) ?? 0;
              int nU = int.tryParse(uC.text) ?? 0;
              int nB = int.tryParse(bC.text) ?? 0;
              int newTotalIn = nD + nP + nU + nB;
              String shopPrefix = selectedShop!.toLowerCase();
              Navigator.pop(context);
              setState(() => isLoading = true);
              await FirebaseFirestore.instance
                  .collection('products_data')
                  .doc(p['id'])
                  .update({
                    '${shopPrefix}_in_D': nD,
                    '${shopPrefix}_in_P': nP,
                    '${shopPrefix}_in_U': nU,
                    '${shopPrefix}_in_B': nB,
                    '${shopPrefix}_stock': newTotalIn,
                    selectedShop == "Cassia"
                            ? "cassia_morning_stock"
                            : "battistini_morning_stock":
                        newTotalIn,
                  });
              _loadShortEatProducts();
            },
            child: const Text("Save Changes"),
          ),
        ],
      ),
    );
  }
}
