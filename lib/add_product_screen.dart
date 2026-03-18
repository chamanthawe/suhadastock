import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'constants.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  // --- Theme Color ---
  final Color darkGreen = const Color(0xFF1B5E20);

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _skuController = TextEditingController();
  final _shopPriceController = TextEditingController();
  final _cassiaStockController = TextEditingController(text: "0");
  final _battistiniStockController = TextEditingController(text: "0");
  final _costController = TextEditingController();
  final _taxController = TextEditingController(text: "10");
  final _profitAmountController = TextEditingController();

  final FocusNode _skuFocusNode = FocusNode();
  final FocusNode _cassiaFocusNode = FocusNode();

  File? _image;
  bool isSaving = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _costController.addListener(_autoCalculateFromCost);
    _taxController.addListener(_autoCalculateFromCost);
    _shopPriceController.addListener(_autoCalculateFromShopPrice);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _skuController.dispose();
    _shopPriceController.dispose();
    _cassiaStockController.dispose();
    _battistiniStockController.dispose();
    _costController.dispose();
    _taxController.dispose();
    _profitAmountController.dispose();
    _skuFocusNode.dispose();
    _cassiaFocusNode.dispose();
    super.dispose();
  }

  // --- පවතින Logic (අත නොතබන ලදී) ---

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
    );
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
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

  Future<void> _saveProduct() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter product name")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final String url =
          "${AppConstants.baseUrl}/products?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}";

      List<Map<String, dynamic>> imageList = [];
      // (Image upload logic should be implemented here if needed)

      final body = {
        "name": _nameController.text,
        "type": "simple",
        "status": "private",
        "regular_price": _priceController.text,
        "sku": _skuController.text,
        "manage_stock": true,
        "stock_quantity": int.tryParse(_cassiaStockController.text) ?? 0,
        "images": imageList,
        "meta_data": [
          {"key": "shop_price", "value": _shopPriceController.text},
          {"key": "battistini_stock", "value": _battistiniStockController.text},
          {"key": "cost_price", "value": _costController.text},
          {"key": "tax_rate", "value": _taxController.text},
          {"key": "profit", "value": _profitAmountController.text},
        ],
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );

      if (response.statusCode == 201) {
        var newProduct = json.decode(response.body);
        String newId = newProduct['id'].toString();

        await FirebaseFirestore.instance
            .collection('products_data')
            .doc(newId)
            .set({
              'shop_price': _shopPriceController.text,
              'profit': _profitAmountController.text,
              'last_updated': FieldValue.serverTimestamp(),
            });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Private Product Added Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception("Failed to create product: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          "Add Private Product",
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
            _buildImageHeader(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildSectionTitle("BASIC INFORMATION"),
                  _buildTextField(
                    _nameController,
                    "Product Name",
                    Icons.inventory,
                  ),
                  const SizedBox(height: 8),
                  _buildSKUField(),

                  const SizedBox(height: 25),
                  _buildSectionTitle("STOCK ALLOCATION"),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _cassiaStockController,
                          "Cassia",
                          Icons.warehouse,
                          isNumber: true,
                          focusNode: _cassiaFocusNode,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _battistiniStockController,
                          "Battistini",
                          Icons.store,
                          isNumber: true,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),
                  _buildSectionTitle("PRICING & PROFIT"),
                  _buildTextField(
                    _costController,
                    "Cost Price (€)",
                    Icons.euro,
                    isNumber: true,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _taxController,
                          "Tax (%)",
                          Icons.percent,
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _profitAmountController,
                          "Profit (€)",
                          Icons.trending_up,
                          isNumber: true,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  _buildTextField(
                    _shopPriceController,
                    "Final Shop Price (€)",
                    Icons.sell,
                    isNumber: true,
                    isBold: true,
                    highlight: true,
                  ),

                  _buildTextField(
                    _priceController,
                    "Web Price (€)",
                    Icons.public,
                    isNumber: true,
                  ),

                  const SizedBox(height: 40),
                  _buildSaveButton(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        color: darkGreen,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Center(
        child: GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                height: 140,
                width: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: _image != null
                    ? ClipOval(child: Image.file(_image!, fit: BoxFit.cover))
                    : Icon(Icons.add_a_photo, size: 50, color: darkGreen),
              ),
              CircleAvatar(
                backgroundColor: Colors.yellow[700],
                radius: 20,
                child: const Icon(
                  Icons.camera_alt,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: darkGreen, width: 4)),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: darkGreen,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSKUField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5),
        ],
      ),
      child: TextField(
        controller: _skuController,
        focusNode: _skuFocusNode,
        cursorColor: darkGreen,
        onSubmitted: (_) =>
            FocusScope.of(context).requestFocus(_cassiaFocusNode),
        decoration: InputDecoration(
          labelText: "Barcode / SKU",
          labelStyle: TextStyle(color: darkGreen.withValues(alpha: 0.7)),
          prefixIcon: Icon(Icons.qr_code_scanner, color: darkGreen),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumber = false,
    bool isBold = false,
    bool highlight = false,
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: highlight ? darkGreen.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
            ),
          ],
          border: highlight
              ? Border.all(color: darkGreen.withValues(alpha: 0.2))
              : null,
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          cursorColor: darkGreen,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 18 : 16,
            color: highlight ? darkGreen : Colors.black87,
          ),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(
              color: darkGreen.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            prefixIcon: Icon(icon, color: darkGreen, size: 22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return isSaving
        ? CircularProgressIndicator(color: darkGreen)
        : ElevatedButton.icon(
            onPressed: _saveProduct,
            icon: const Icon(Icons.save_rounded),
            label: const Text(
              "SAVE PRIVATE PRODUCT",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: darkGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 3,
            ),
          );
  }
}
