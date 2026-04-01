import 'dart:io';
import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

class LoyalCustomerProfile extends StatefulWidget {
  final String? customerId;
  final Map<String, dynamic>? existingData;

  const LoyalCustomerProfile({super.key, this.customerId, this.existingData});

  @override
  _LoyalCustomerProfileState createState() => _LoyalCustomerProfileState();
}

class _LoyalCustomerProfileState extends State<LoyalCustomerProfile> {
  final _formKey = GlobalKey<FormState>();
  final ScreenshotController _screenshotController = ScreenshotController();

  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  late TextEditingController _barcodeController;
  late TextEditingController _phoneController;
  final TextEditingController _prodIdController = TextEditingController();
  final TextEditingController _prodPriceController = TextEditingController();

  bool _isLoyalDiscountActive = false;
  bool _isBusinessCustomer = false;
  String? _selectedShop;
  List<Map<String, dynamic>> _businessProducts = [];
  final Color primaryGreen = Colors.green.shade800;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingData?['name'] ?? '',
    );
    _surnameController = TextEditingController(
      text: widget.existingData?['surname'] ?? '',
    );
    _barcodeController = TextEditingController(
      text: widget.existingData?['barcode'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.existingData?['phone'] ?? '',
    );
    _isLoyalDiscountActive = widget.existingData?['loyal_discount'] ?? false;
    _isBusinessCustomer = widget.existingData?['special_for_business'] ?? false;
    _selectedShop = widget.existingData?['shop'];
    _businessProducts = List<Map<String, dynamic>>.from(
      widget.existingData?['business_pricing'] ?? [],
    );
  }

  // --- 🔥 නව Delete Function එක 🔥 ---
  Future<void> _deleteCustomer() async {
    if (widget.customerId == null) return;

    // තහවුරු කරගැනීමේ Dialog එක
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Delete Profile?"),
            content: const Text(
              "ඔබට මෙම පාරිභෝගිකයාගේ දත්ත සම්පූර්ණයෙන්ම ඉවත් කිරීමට අවශ්‍යද?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await FirebaseFirestore.instance
            .collection('loyal_customers')
            .doc(widget.customerId)
            .delete();
        Navigator.pop(context); // Profile එකෙන් ඉවත් වීම
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile Deleted Successfully")),
        );
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }

  // --- Creative Virtual Card Design ---
  Widget _buildVirtualCardWidget(String name, String barcode) {
    return Container(
      width: 450,
      height: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Container(
            height: 100,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "LOYALTY\nMEMBER",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1.5,
                  ),
                ),
                const Icon(Icons.stars, color: Colors.white, size: 50),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 25,
            right: 25,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      "SUHADA INVENTORY",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: barcode,
                      width: 140,
                      height: 55,
                      drawText: false,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      barcode,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCard(String phone, String name, String barcode) async {
    try {
      final Uint8List imageBytes = await _screenshotController
          .captureFromWidget(_buildVirtualCardWidget(name, barcode));
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/suhada_loyalty_card.png';
      final file = File(path);
      await file.writeAsBytes(imageBytes);
      await Share.shareXFiles([
        XFile(path),
      ], text: 'Hi $name, here is your Suhada Loyalty Card! ✨');
    } catch (e) {
      debugPrint("Sharing error: $e");
    }
  }

  Future<void> _saveCustomer() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedShop == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Please select a shop")));
        return;
      }
      final data = {
        'name': _nameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'shop': _selectedShop,
        'barcode': _barcodeController.text.trim(),
        'phone': _phoneController.text.trim(),
        'loyal_discount': _isLoyalDiscountActive,
        'special_for_business': _isBusinessCustomer,
        'business_pricing': _isBusinessCustomer ? _businessProducts : [],
        'updatedAt': DateTime.now(),
      };
      try {
        if (widget.customerId == null) {
          data['createdAt'] = DateTime.now();
          await FirebaseFirestore.instance
              .collection('loyal_customers')
              .add(data);
          _showSuccessAndShare();
        } else {
          await FirebaseFirestore.instance
              .collection('loyal_customers')
              .doc(widget.customerId)
              .update(data);
          Navigator.pop(context);
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }

  void _showSuccessAndShare() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Success!"),
        content: const Text(
          "Customer ලියාපදිංචි කළා. Loyalty Card එක WhatsApp මගින් යවමුද?",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("Skip"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _shareCard(
                _phoneController.text,
                _nameController.text,
                _barcodeController.text,
              );
              Navigator.pop(context);
            },
            child: const Text(
              "Share Card",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        title: Text(
          widget.customerId == null ? "Register Partner" : "Edit Profile",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: primaryGreen,
        centerTitle: true,
        // 🔥 Edit කරන වෙලාවට විතරක් Delete Button එක පෙන්වයි 🔥
        actions: [
          if (widget.customerId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _deleteCustomer,
              tooltip: "Delete Customer",
            ),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: _buildDecor("First Name *", Icons.person),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _surnameController,
                decoration: _buildDecor("Surname *", Icons.person_outline),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedShop,
                hint: const Text("Select Shop *"),
                items: ['Battistini', 'Cassia']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedShop = val),
                decoration: _buildDecor("Shop", Icons.storefront),
                validator: (v) => v == null ? "Required" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcodeController,
                decoration: _buildDecor("Barcode ID *", Icons.qr_code),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: _buildDecor("Phone *", Icons.phone_android),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 25),
              _buildPrivilegeCard(),
              if (_isBusinessCustomer) _buildBusinessSection(),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _saveCustomer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  "REGISTER & SAVE",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _buildDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primaryGreen),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildPrivilegeCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          SwitchListTile(
            activeColor: primaryGreen,
            title: const Text("Loyal Discount"),
            value: _isLoyalDiscountActive,
            onChanged: (v) => setState(() => _isLoyalDiscountActive = v),
          ),
          SwitchListTile(
            activeColor: primaryGreen,
            title: const Text("Business Mode"),
            value: _isBusinessCustomer,
            onChanged: (v) => setState(() => _isBusinessCustomer = v),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessSection() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _prodIdController,
                  decoration: const InputDecoration(labelText: "Product ID"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _prodPriceController,
                  decoration: const InputDecoration(labelText: "Price (€)"),
                ),
              ),
              IconButton(
                onPressed: _addBusinessProduct,
                icon: const Icon(
                  Icons.add_box,
                  color: Colors.blueGrey,
                  size: 30,
                ),
              ),
            ],
          ),
          const Divider(),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _businessProducts.length,
            itemBuilder: (context, i) => ListTile(
              title: Text("ID: ${_businessProducts[i]['p_id']}"),
              trailing: Text("€${_businessProducts[i]['p_price']}"),
              leading: GestureDetector(
                onTap: () => setState(() => _businessProducts.removeAt(i)),
                child: const Icon(Icons.remove_circle, color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addBusinessProduct() {
    if (_prodIdController.text.isNotEmpty &&
        _prodPriceController.text.isNotEmpty) {
      setState(() {
        _businessProducts.add({
          'p_id': _prodIdController.text.trim(),
          'p_price': double.tryParse(_prodPriceController.text) ?? 0.0,
        });
        _prodIdController.clear();
        _prodPriceController.clear();
      });
    }
  }
}
