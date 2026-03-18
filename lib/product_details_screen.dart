import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'constants.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Map product;
  const ProductDetailsScreen({super.key, required this.product});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  // --- Theme Color ---
  final Color darkGreen = const Color(0xFF1B5E20);

  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _skuController;
  late TextEditingController _shopPriceController;
  late TextEditingController _discountPriceController;
  late TextEditingController _cassiaStockController;
  late TextEditingController _battistiniStockController;

  final _costController = TextEditingController();
  final _taxController = TextEditingController(text: "10");
  final _profitAmountController = TextEditingController();

  bool isUpdating = false;
  bool isLooseProduct = false; // Loose (Kg) ද යන්න හඳුනා ගැනීමට

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product['name']);
    _priceController = TextEditingController(text: widget.product['price']);
    _skuController = TextEditingController(text: widget.product['sku']);

    _cassiaStockController = TextEditingController(
      text: widget.product['stock_quantity']?.toString() ?? "0",
    );

    List meta = widget.product['meta_data'] ?? [];
    _shopPriceController = TextEditingController(
      text: _getMetaValue(meta, 'shop_price'),
    );

    _discountPriceController = TextEditingController(text: "0.00");

    _battistiniStockController = TextEditingController(
      text: _getMetaValue(meta, 'battistini_stock', defaultValue: "0"),
    );

    _taxController.text = _getMetaValue(meta, 'tax_rate', defaultValue: "10");

    String savedCost = _getMetaValue(meta, 'cost_price');
    if (savedCost.isNotEmpty) _costController.text = savedCost;

    String savedProfit = _getMetaValue(meta, 'profit');
    if (savedProfit.isNotEmpty) {
      _profitAmountController.text = savedProfit;
    } else {
      _calculateProfitInitially();
    }

    _loadFirestoreData();

    _costController.addListener(_autoCalculateFromCost);
    _taxController.addListener(_autoCalculateFromCost);
    _shopPriceController.addListener(_autoCalculateFromShopPrice);
    _skuController.addListener(_instantBarcodeSync);

    _syncToFirestoreLocally();
  }

  Future<void> _loadFirestoreData() async {
    try {
      var doc = await FirebaseFirestore.instance
          .collection('products_data')
          .doc(widget.product['id'].toString())
          .get();
      if (doc.exists && doc.data() != null) {
        var data = doc.data()!;
        setState(() {
          isLooseProduct = data['is_loose'] ?? false;
          _shopPriceController.text =
              data['shop_price']?.toString() ?? _shopPriceController.text;
          _discountPriceController.text =
              data['discount_price']?.toString() ?? "0.00";
          _profitAmountController.text =
              data['profit']?.toString() ?? _profitAmountController.text;
          _cassiaStockController.text = data['cassia_stock']?.toString() ?? "0";
          _battistiniStockController.text =
              data['battistini_stock']?.toString() ?? "0";
        });
      }
    } catch (e) {
      debugPrint("Load Firestore Data Error: $e");
    }
  }

  @override
  void dispose() {
    _skuController.removeListener(_instantBarcodeSync);
    _nameController.dispose();
    _priceController.dispose();
    _skuController.dispose();
    _shopPriceController.dispose();
    _discountPriceController.dispose();
    _cassiaStockController.dispose();
    _battistiniStockController.dispose();
    _costController.dispose();
    _taxController.dispose();
    _profitAmountController.dispose();
    super.dispose();
  }

  // --- Helpers ---
  void _instantBarcodeSync() {
    if (_skuController.text.isNotEmpty) _syncToFirestoreLocally();
  }

  Future<void> _syncToFirestoreLocally() async {
    final String productId = widget.product['id'].toString();
    try {
      await FirebaseFirestore.instance
          .collection('products_data')
          .doc(productId)
          .set({
            'name': _nameController.text,
            'sku': _skuController.text.trim(),
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Instant Sync Error: $e");
    }
  }

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              setState(() {
                _skuController.text = barcodes.first.rawValue ?? "";
              });
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }

  String _getMetaValue(List meta, String key, {String defaultValue = ""}) {
    var found = meta.firstWhere((m) => m['key'] == key, orElse: () => null);
    return found != null ? found['value'].toString() : defaultValue;
  }

  // --- Calculations ---
  void _calculateProfitInitially() {
    double shopPrice = double.tryParse(_shopPriceController.text) ?? 0;
    double cost = double.tryParse(_costController.text) ?? 0;
    double tax = double.tryParse(_taxController.text) ?? 10;
    if (shopPrice > 0 && cost > 0) {
      double costWithTax = cost + (cost * tax / 100);
      _profitAmountController.text = (shopPrice - costWithTax).toStringAsFixed(
        2,
      );
    }
  }

  void _autoCalculateFromCost() {
    double cost = double.tryParse(_costController.text) ?? 0;
    double tax = double.tryParse(_taxController.text) ?? 10;
    if (cost > 0) {
      double costWithTax = cost + (cost * tax / 100);
      double autoProfit = costWithTax * 0.30;
      _shopPriceController.removeListener(_autoCalculateFromShopPrice);
      _profitAmountController.text = autoProfit.toStringAsFixed(2);
      _shopPriceController.text = (costWithTax + autoProfit).toStringAsFixed(2);
      _shopPriceController.addListener(_autoCalculateFromShopPrice);
    }
  }

  void _autoCalculateFromShopPrice() {
    double shopPrice = double.tryParse(_shopPriceController.text) ?? 0;
    double tax = double.tryParse(_taxController.text) ?? 10;
    double cost = double.tryParse(_costController.text) ?? 0;
    if (shopPrice > 0 && cost > 0) {
      double costWithTax = cost + (cost * tax / 100);
      _profitAmountController.text = (shopPrice - costWithTax).toStringAsFixed(
        2,
      );
    }
  }

  void _onProfitManualChange(String val) {
    double cost = double.tryParse(_costController.text) ?? 0;
    double tax = double.tryParse(_taxController.text) ?? 10;
    double profit = double.tryParse(val) ?? 0;
    if (cost > 0) {
      double costWithTax = cost + (cost * tax / 100);
      _shopPriceController.removeListener(_autoCalculateFromShopPrice);
      _shopPriceController.text = (costWithTax + profit).toStringAsFixed(2);
      _shopPriceController.addListener(_autoCalculateFromShopPrice);
    }
  }

  // --- Main Sync Logic ---
  Future<void> _updateProduct() async {
    setState(() => isUpdating = true);
    final String productId = widget.product['id'].toString();

    // දශම 3 Logic එක මෙතැනදී ක්‍රියාත්මක වේ
    dynamic cassiaStockValue;
    dynamic battistiniStockValue;

    if (isLooseProduct) {
      double cVal = double.tryParse(_cassiaStockController.text) ?? 0.0;
      double bVal = double.tryParse(_battistiniStockController.text) ?? 0.0;
      cassiaStockValue = double.parse(cVal.toStringAsFixed(3));
      battistiniStockValue = double.parse(bVal.toStringAsFixed(3));
    } else {
      cassiaStockValue = int.tryParse(_cassiaStockController.text) ?? 0;
      battistiniStockValue = int.tryParse(_battistiniStockController.text) ?? 0;
    }

    try {
      // 1. Firestore Sync
      await FirebaseFirestore.instance
          .collection('products_data')
          .doc(productId)
          .set({
            'name': _nameController.text,
            'sku': _skuController.text.trim(),
            'shop_price': _shopPriceController.text,
            'discount_price': _discountPriceController.text,
            'profit': _profitAmountController.text,
            'cassia_stock': cassiaStockValue,
            'battistini_stock': battistiniStockValue,
            'is_loose': isLooseProduct,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // 2. WooCommerce Sync
      final String url =
          "${AppConstants.baseUrl}/products/$productId?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}";
      Map<String, dynamic> body = {
        "name": _nameController.text,
        "sku": _skuController.text.trim(),
        "meta_data": [
          {"key": "shop_price", "value": _shopPriceController.text},
          {"key": "battistini_stock", "value": battistiniStockValue.toString()},
          {"key": "cassia_stock", "value": cassiaStockValue.toString()},
          {"key": "cost_price", "value": _costController.text},
          {"key": "tax_rate", "value": _taxController.text},
          {"key": "profit", "value": _profitAmountController.text},
          {"key": "is_loose", "value": isLooseProduct ? "yes" : "no"},
        ],
      };

      if (isLooseProduct) {
        body["manage_stock"] = false; // Kg නම් Woocommerce stock disable කරයි
      } else {
        body["manage_stock"] = true;
        body["stock_quantity"] = cassiaStockValue;
        body["stock_status"] = cassiaStockValue <= 0 ? "outofstock" : "instock";
      }

      final response = await http.put(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Success! 3rd Decimal Sync Completed."),
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: ${response.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String imageUrl =
        (widget.product['images'] != null &&
            widget.product['images'].isNotEmpty)
        ? widget.product['images'][0]['src']
        : "";

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Product Details",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: darkGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopImageSection(imageUrl),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildCard("BASIC INFORMATION", [
                    _buildTextField(
                      _nameController,
                      "Product Name",
                      Icons.inventory_2,
                    ),
                    _buildBarcodeField(),
                    SwitchListTile(
                      title: const Text(
                        "Is Loose Product (Kg)?",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        "Sell by weight with 3 decimal precision",
                      ),
                      value: isLooseProduct,
                      activeColor: darkGreen,
                      onChanged: (val) => setState(() => isLooseProduct = val),
                    ),
                  ]),
                  _buildCard(
                    "STOCK CONTROL (${isLooseProduct ? 'Kg' : 'Qty'})",
                    [
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              _cassiaStockController,
                              "Cassia Stock",
                              Icons.warehouse,
                              isNumber: true,
                              isDecimal: isLooseProduct,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              _battistiniStockController,
                              "Battistini Stock",
                              Icons.storefront,
                              isNumber: true,
                              isDecimal: isLooseProduct,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _buildCard("PRICE & PROFIT ANALYSIS", [
                    _buildTextField(
                      _costController,
                      "Cost Price (€)",
                      Icons.euro_symbol,
                      isNumber: true,
                      isDecimal: true,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            _taxController,
                            "Tax (%)",
                            Icons.percent,
                            isNumber: true,
                            isDecimal: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _buildManualProfitField()),
                      ],
                    ),
                    const Divider(height: 30),
                    _buildTextField(
                      _shopPriceController,
                      "Final Shop Price (€)",
                      Icons.sell,
                      isNumber: true,
                      isDecimal: true,
                      isBold: true,
                      highlight: true,
                    ),
                    _buildTextField(
                      _discountPriceController,
                      "Discount (Firestore Only)",
                      Icons.local_offer,
                      isNumber: true,
                      isDecimal: true,
                    ),
                    _buildTextField(
                      _priceController,
                      "Web Price",
                      Icons.language,
                      isNumber: true,
                      isDecimal: true,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _buildSaveButton(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI Components ---
  Widget _buildTopImageSection(String url) => Container(
    width: double.infinity,
    height: 200,
    decoration: BoxDecoration(
      color: darkGreen,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(30),
        bottomRight: Radius.circular(30),
      ),
    ),
    child: Center(
      child: Container(
        height: 160,
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: url.isNotEmpty
              ? Image.network(url, fit: BoxFit.cover)
              : Icon(Icons.image, size: 80, color: Colors.grey[300]),
        ),
      ),
    ),
  );

  Widget _buildCard(String title, List<Widget> children) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.1),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: darkGreen,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumber = false,
    bool isDecimal = false,
    bool isBold = false,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        cursorColor: darkGreen,
        inputFormatters: isNumber
            ? [
                FilteringTextInputFormatter.allow(
                  RegExp(isDecimal ? r'^\d*\.?\d{0,3}' : r'^\d*'),
                ),
              ]
            : [],
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: highlight ? darkGreen : Colors.black,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(
            icon,
            color: highlight ? darkGreen : Colors.grey[600],
            size: 20,
          ),
          filled: true,
          fillColor: highlight ? darkGreen.withOpacity(0.05) : Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: darkGreen, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildBarcodeField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _skuController,
      decoration: InputDecoration(
        labelText: "Barcode / SKU",
        prefixIcon: const Icon(Icons.qr_code_2, color: Colors.grey, size: 20),
        suffixIcon: IconButton(
          icon: Icon(Icons.qr_code_scanner, color: darkGreen),
          onPressed: _openScanner,
        ),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _buildManualProfitField() => TextField(
    controller: _profitAmountController,
    keyboardType: TextInputType.number,
    onChanged: _onProfitManualChange,
    decoration: InputDecoration(
      labelText: "Profit (€)",
      prefixIcon: const Icon(Icons.trending_up, color: Colors.green, size: 20),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _buildSaveButton() => isUpdating
      ? CircularProgressIndicator(color: darkGreen)
      : ElevatedButton.icon(
          onPressed: _updateProduct,
          icon: const Icon(Icons.cloud_upload),
          label: const Text(
            "SAVE & SYNC DATA",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: darkGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        );
}
