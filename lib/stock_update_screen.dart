import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'constants.dart';

class StockUpdateScreen extends StatefulWidget {
  const StockUpdateScreen({super.key});

  @override
  State<StockUpdateScreen> createState() => _StockUpdateScreenState();
}

class _StockUpdateScreenState extends State<StockUpdateScreen> {
  // --- Theme Color ---
  final Color darkGreen = const Color(0xFF1B5E20);

  String? selectedShop;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  final FocusNode _barcodeFocusNode = FocusNode();
  String _barcodeBuffer = "";

  dynamic selectedProduct;
  bool isSearching = false;
  bool isUpdating = false;

  @override
  void dispose() {
    _barcodeFocusNode.dispose();
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // --- පවතින Logic (අත නොතබන ලදී) ---

  Future<void> _searchProduct(String query) async {
    if (query.isEmpty) return;

    setState(() {
      isSearching = true;
      selectedProduct = null;
      _searchController.text = query;
    });

    try {
      String finalSearchQuery = query;

      var firestoreDoc = await FirebaseFirestore.instance
          .collection('products_data')
          .where('sku', isEqualTo: query.trim())
          .limit(1)
          .get();

      if (firestoreDoc.docs.isNotEmpty) {
        finalSearchQuery = firestoreDoc.docs.first.id;
        final String url =
            "${AppConstants.baseUrl}/products/$finalSearchQuery?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}";

        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          setState(() => selectedProduct = json.decode(response.body));
          return;
        }
      }

      final String url =
          "${AppConstants.baseUrl}/products?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}&search=$query&per_page=1";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        List results = json.decode(response.body);
        if (results.isNotEmpty) {
          setState(() => selectedProduct = results.first);
        } else {
          _showSnackBar("No product found for: $query", Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar("Search Error: $e", Colors.red);
    } finally {
      setState(() => isSearching = false);
    }
  }

  Future<void> _updateStock() async {
    if (selectedProduct == null || _quantityController.text.isEmpty) {
      _showSnackBar(
        "Please select a product and enter quantity",
        Colors.orange,
      );
      return;
    }

    setState(() => isUpdating = true);
    int addQty = int.tryParse(_quantityController.text) ?? 0;
    int productId = selectedProduct['id'];

    int currentCassia =
        int.tryParse(selectedProduct['stock_quantity']?.toString() ?? "0") ?? 0;
    int currentBattistini =
        int.tryParse(_getMeta(selectedProduct, 'battistini_stock')) ?? 0;

    int newCassia = currentCassia;
    int newBattistini = currentBattistini;

    if (selectedShop == "Cassia") {
      newCassia += addQty;
    } else {
      newBattistini += addQty;
    }

    try {
      final String url =
          "${AppConstants.baseUrl}/products/$productId?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}";

      final body = {
        "stock_quantity": newCassia,
        "meta_data": [
          {"key": "battistini_stock", "value": newBattistini.toString()},
        ],
      };

      final response = await http.put(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        bool isBat = selectedShop == "Battistini";
        String targetKey = isBat ? "battistini_stock" : "cassia_stock";

        await FirebaseFirestore.instance
            .collection('products_data')
            .doc(productId.toString())
            .set({
              targetKey: isBat ? newBattistini : newCassia,
              'last_updated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

        _showSnackBar("Stock Updated Successfully!", Colors.green);

        setState(() {
          selectedProduct = null;
          _quantityController.clear();
          _searchController.clear();
        });

        _barcodeFocusNode.requestFocus();
      }
    } catch (e) {
      _showSnackBar("Update Error: $e", Colors.red);
    } finally {
      setState(() => isUpdating = false);
    }
  }

  String _getMeta(Map p, String key) {
    List meta = p['meta_data'] ?? [];
    var found = meta.firstWhere((m) => m['key'] == key, orElse: () => null);
    return found != null ? found['value'].toString() : "0";
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _barcodeFocusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (_barcodeBuffer.trim().isNotEmpty) {
              _searchProduct(_barcodeBuffer.trim());
              _barcodeBuffer = "";
            }
          } else if (event.character != null) {
            _barcodeBuffer += event.character!;
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text(
            "Stock Update",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: darkGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeaderSection(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel("SELECT BRANCH"),
                    _buildBranchSelector(),
                    const SizedBox(height: 20),
                    _buildSectionLabel("SEARCH PRODUCT"),
                    _buildSearchField(),
                    const SizedBox(height: 20),
                    if (isSearching)
                      Center(
                        child: CircularProgressIndicator(color: darkGreen),
                      ),
                    if (selectedProduct != null) ...[
                      _buildProductCard(),
                      const SizedBox(height: 25),
                      _buildSectionLabel("ADD NEW QUANTITY"),
                      _buildQuantityField(),
                      const SizedBox(height: 30),
                      _buildUpdateButton(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() => Container(
    width: double.infinity,
    padding: const EdgeInsets.only(bottom: 30, left: 16, right: 16),
    decoration: BoxDecoration(
      color: darkGreen,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(30),
        bottomRight: Radius.circular(30),
      ),
    ),
    child: const Text(
      "Manage your branch inventory efficiently",
      style: TextStyle(color: Colors.white70, fontSize: 14),
      textAlign: TextAlign.center,
    ),
  );

  Widget _buildSectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: darkGreen,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _buildBranchSelector() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
      ],
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedShop,
        hint: const Text("Choose Target Branch"),
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: darkGreen),
        items: ["Cassia", "Battistini"]
            .map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(
                  s,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            )
            .toList(),
        onChanged: (val) {
          setState(() => selectedShop = val);
          _barcodeFocusNode.requestFocus();
        },
      ),
    ),
  );

  Widget _buildSearchField() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
      ],
    ),
    child: TextField(
      controller: _searchController,
      onSubmitted: (value) => _searchProduct(value),
      decoration: InputDecoration(
        hintText: selectedShop == null
            ? "Select branch first..."
            : "Scan or Type Product...",
        prefixIcon: Icon(Icons.qr_code_scanner, color: darkGreen),
        suffixIcon: IconButton(
          icon: Icon(Icons.search, color: darkGreen),
          onPressed: () => _searchProduct(_searchController.text),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
      ),
    ),
  );

  Widget _buildProductCard() => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Colors.grey[200]!),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _buildProductImage(selectedProduct),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedProduct['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "SKU: ${selectedProduct['sku'] ?? 'N/A'}",
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _stockChip(
                      "Cassia: ${selectedProduct['stock_quantity'] ?? 0}",
                      Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _stockChip(
                      "Bat: ${_getMeta(selectedProduct, 'battistini_stock')}",
                      Colors.teal,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildQuantityField() => TextField(
    controller: _quantityController,
    keyboardType: TextInputType.number,
    autofocus: true,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    decoration: InputDecoration(
      hintText: "0",
      filled: true,
      fillColor: darkGreen.withValues(alpha: 0.05),
      prefixIcon: Icon(Icons.add_box, color: darkGreen, size: 30),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: darkGreen, width: 2),
      ),
    ),
    onSubmitted: (_) => _updateStock(),
  );

  Widget _buildUpdateButton() => isUpdating
      ? Center(child: CircularProgressIndicator(color: darkGreen))
      : ElevatedButton.icon(
          onPressed: _updateStock,
          icon: const Icon(Icons.sync_rounded),
          label: const Text(
            "UPDATE STOCK NOW",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: darkGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 2,
          ),
        );

  Widget _buildProductImage(dynamic p) {
    String imageUrl = (p['images'] != null && (p['images'] as List).isNotEmpty)
        ? p['images'][0]['src']
        : "";
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: imageUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, color: Colors.grey),
              ),
            )
          : const Icon(Icons.image, color: Colors.grey, size: 40),
    );
  }

  Widget _stockChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
    ),
  );
}
