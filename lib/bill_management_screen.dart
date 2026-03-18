import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class BillManagementScreen extends StatefulWidget {
  const BillManagementScreen({super.key});

  @override
  State<BillManagementScreen> createState() => _BillManagementScreenState();
}

class _BillManagementScreenState extends State<BillManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bill Management")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bills')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: const Icon(Icons.receipt, color: Colors.teal),
                  title: Text("${data['category']} - €${data['amount']}"),
                  subtitle: Text("${data['date']} | ${data['shop']}"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // බිල්පතේ විස්තර බැලීමට අවශ්‍ය නම් මෙහි ලියන්න
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddBillScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// --- බිල්පතක් ඇතුළත් කරන Screen එක ---
class AddBillScreen extends StatefulWidget {
  const AddBillScreen({super.key});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String selectedCategory = "Electricity";
  String selectedShop = "Cassia";
  File? _image;
  bool isSaving = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _saveBill() async {
    if (_amountController.text.isEmpty) return;
    setState(() => isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('bills').add({
        'amount': _amountController.text,
        'category': selectedCategory,
        'shop': selectedShop,
        'note': _noteController.text,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'timestamp': FieldValue.serverTimestamp(),
        // දැනට image path එක පමණක් සේව් කරයි.
        // පසුව Firebase Storage භාවිතා කර upload කළ හැක.
        'image_path': _image?.path ?? "",
      });
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add New Bill")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: selectedShop,
              items: [
                "Cassia",
                "Battistini",
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => selectedShop = v!),
              decoration: const InputDecoration(labelText: "Shop"),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: selectedCategory,
              items: [
                "Electricity",
                "Water",
                "Rent",
                "Staff",
                "Other",
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => selectedCategory = v!),
              decoration: const InputDecoration(labelText: "Category"),
            ),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount (€)"),
            ),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: "Note"),
            ),
            const SizedBox(height: 20),
            _image == null
                ? ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Take Photo"),
                  )
                : Image.file(_image!, height: 150),
            const SizedBox(height: 30),
            isSaving
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _saveBill,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.teal,
                    ),
                    child: const Text(
                      "Save Bill",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
