import 'dart:convert'; // 👈 Base64 සහ Notification දත්ත සඳහා අවශ්‍යයි
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class BillManagementScreen extends StatefulWidget {
  const BillManagementScreen({super.key});

  @override
  State<BillManagementScreen> createState() => _BillManagementScreenState();
}

class _BillManagementScreenState extends State<BillManagementScreen> {
  final Color darkGreen = const Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Bill Management",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: darkGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bills')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: darkGreen));
          }
          var docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No bills recorded yet.",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: Hero(
                    tag: docs[index].id,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: darkGreen.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          (data['image_data'] != null &&
                              data['image_data'] != "")
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(data['image_data']),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                    Icon(Icons.receipt_long, color: darkGreen),
                              ),
                            )
                          : Icon(Icons.receipt_long, color: darkGreen),
                    ),
                  ),
                  title: Text(
                    "${data['bill_name']}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    "€${data['amount']} • ${data['shop']}\n${data['date_time']}",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: darkGreen,
                  ),
                  onTap: () => _viewBillDetails(data, docs[index].id),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: darkGreen,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddBillScreen()),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _viewBillDetails(Map<String, dynamic> data, String docId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    data['category'] ?? "Bill Detail",
                    style: TextStyle(
                      color: darkGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                data['bill_name'],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Recorded on: ${data['date_time']}",
                style: const TextStyle(color: Colors.grey),
              ),
              const Divider(height: 30),
              _detailRow(Icons.euro, "Amount", "€${data['amount']}"),
              _detailRow(Icons.store, "Shop", data['shop']),
              _detailRow(
                Icons.notes,
                "Description",
                data['note'] == "" ? "No description" : data['note'],
              ),
              const SizedBox(height: 20),
              const Text(
                "Bill Attachment",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (data['image_data'] != null && data['image_data'] != "")
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.memory(
                        base64Decode(data['image_data']),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Share.share(
                                "Bill Name: ${data['bill_name']}\nAmount: €${data['amount']}\nShop: ${data['shop']}",
                              );
                            },
                            icon: const Icon(Icons.share, color: Colors.white),
                            label: const Text(
                              "Share Bill Info",
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: darkGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                const Center(
                  child: Text(
                    "No image attached",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: darkGreen),
          const SizedBox(width: 10),
          Text("$title: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// --- ➕ Add Bill Screen ---
class AddBillScreen extends StatefulWidget {
  const AddBillScreen({super.key});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen> {
  final _amountController = TextEditingController();
  final _billNameController = TextEditingController();
  final _noteController = TextEditingController();
  final Color darkGreen = const Color(0xFF1B5E20);

  String selectedCategory = "Electricity";
  String selectedShop = "Cassia";
  File? _image;
  bool isSaving = false;

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 20, // 👈 MB ගණන අඩු කිරීමට
      maxWidth: 800,
    );
    if (picked != null) setState(() => _image = File(picked.path));
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text("Take a Photo"),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text("Choose from Gallery"),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Future<void> _saveBill() async {
    if (_billNameController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill required fields!")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      String base64Image = "";
      if (_image != null) {
        final bytes = await _image!.readAsBytes();
        base64Image = base64Encode(bytes);
      }

      // 1. Bill එක Save කිරීම
      await FirebaseFirestore.instance.collection('bills').add({
        'bill_name': _billNameController.text.trim(),
        'amount': _amountController.text.trim(),
        'category': selectedCategory,
        'shop': selectedShop,
        'note': _noteController.text.trim(),
        'date_time': DateFormat('yyyy-MM-dd | hh:mm a').format(DateTime.now()),
        'timestamp': FieldValue.serverTimestamp(),
        'image_data': base64Image,
      });

      // 2. 🔔 Notification Panel එකට Notification එකක් යැවීම
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'bill_entry', // NotificationPanel එකට අවශ්‍ය type එක
        'title': 'New Bill Added',
        'bill_name': _billNameController.text.trim(),
        'amount': _amountController.text.trim(),
        'shop': selectedShop,
        'image_data': base64Image, // Notification එකේ image එක පෙන්වීමට
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Add New Bill",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: darkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("Shop"),
            DropdownButtonFormField<String>(
              value: selectedShop,
              items: [
                "Cassia",
                "Battistini",
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => selectedShop = v!),
              decoration: _inputDecoration("Shop"),
            ),
            const SizedBox(height: 15),
            _buildLabel("Category"),
            DropdownButtonFormField<String>(
              value: selectedCategory,
              items: [
                "Electricity",
                "Water",
                "Rent",
                "Staff",
                "Stock Purchase",
                "Other",
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => selectedCategory = v!),
              decoration: _inputDecoration("Category"),
            ),
            const SizedBox(height: 15),
            _buildLabel("Bill Name"),
            TextField(
              controller: _billNameController,
              decoration: _inputDecoration("e.g. Electricity March"),
            ),
            const SizedBox(height: 15),
            _buildLabel("Amount (€)"),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration("0.00"),
            ),
            const SizedBox(height: 15),
            _buildLabel("Note"),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: _inputDecoration("Short description..."),
            ),
            const SizedBox(height: 20),
            _buildLabel("Attachment"),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: _showImagePickerOptions,
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _image == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo,
                              size: 40,
                              color: darkGreen.withOpacity(0.5),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Capture or Upload Photo",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.file(_image!, fit: BoxFit.cover),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: isSaving
                  ? Center(child: CircularProgressIndicator(color: darkGreen))
                  : ElevatedButton(
                      onPressed: _saveBill,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: darkGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "SAVE BILL",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontWeight: FontWeight.bold, color: darkGreen),
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.grey[50],
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: darkGreen, width: 1.5),
    ),
  );
}
