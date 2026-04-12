import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AfterPayScreen extends StatefulWidget {
  final double totalAmount;
  final List cartItems;

  const AfterPayScreen({
    super.key,
    required this.totalAmount,
    required this.cartItems,
  });

  @override
  State<AfterPayScreen> createState() => _AfterPayScreenState();
}

class _AfterPayScreenState extends State<AfterPayScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isSaving = false;
  bool _sendWhatsAppCheck = true;

  // 🟢 අලුත් Customer සඳහා Shop එක තෝරා ගැනීමට
  String _selectedShopForNewCustomer = "";

  // Green Theme Colors
  final Color primaryGreen = const Color(0xFF1B5E20);
  final Color accentGreen = const Color(0xFF2E7D32);

  // 🟢 App එකේ මුලින්ම තෝරන Shop එක (Default එකක් ලෙස)
  Future<String> _getSavedShopName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_shop') ?? "Suhada Inventory";
  }

  double _calculateTransactionProfit() {
    double totalProfit = 0;
    for (var item in widget.cartItems) {
      double p = double.tryParse(item['profit']?.toString() ?? "0") ?? 0.0;
      double q = double.tryParse(item['qty']?.toString() ?? "1") ?? 1.0;
      totalProfit += (p * q);
    }
    return totalProfit;
  }

  void _confirmCreditOrder(Map<String, dynamic> customerData, String docId) {
    String name = customerData['name'] ?? "Unknown";
    String phone = customerData['phone'] ?? "";
    // 🟢 Customer ගේ දත්ත වලින් Shop එක ගන්නවා
    String customerShop = customerData['shop'] ?? "";

    double currentDebt =
        double.tryParse(customerData['total_debt']?.toString() ?? "0") ?? 0.0;
    double limit =
        double.tryParse(customerData['credit_limit']?.toString() ?? "50.0") ??
        50.0;
    bool isOverLimit = (currentDebt + widget.totalAmount) > limit;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            isOverLimit ? "⚠️ LIMIT EXCEEDED" : "Confirm Credit Record",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isOverLimit ? Colors.red : Colors.black,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Customer: $name", style: const TextStyle(fontSize: 16)),
              // 🟢 Shop එක පෙන්වීම (අවශ්‍ය නම් පමණක්)
              if (customerShop.isNotEmpty)
                Text(
                  "Shop: $customerShop",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              const SizedBox(height: 5),
              Text(
                "Total Amount: €${widget.totalAmount.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isOverLimit ? Colors.red : primaryGreen,
                ),
              ),
              const Divider(height: 30),
              SwitchListTile(
                title: const Text(
                  "Send WhatsApp Notification",
                  style: TextStyle(fontSize: 14),
                ),
                secondary: const Icon(Icons.chat, color: Colors.green),
                value: _sendWhatsAppCheck,
                activeColor: primaryGreen,
                onChanged: (val) {
                  setDialogState(() => _sendWhatsAppCheck = val);
                  setState(() => _sendWhatsAppCheck = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            if (!isOverLimit)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  // 🟢 CustomerShop එක function එකට යවනවා
                  _processCreditOrder(docId, name, phone, customerShop);
                },
                child: const Text("Confirm & Save"),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _processCreditOrder(
    String docId,
    String name,
    String phone,
    String customerShop, // 🟢 Shop එක parameter එකක් ලෙස ගත්තා
  ) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    double transactionProfit = _calculateTransactionProfit();

    // 🟢 Customer ගේ shop එකක් නැත්නම් පමණක් default shop එක ගන්නවා
    String activeShop = customerShop.isNotEmpty
        ? customerShop
        : await _getSavedShopName();

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('customers')
          .doc(docId);
      batch.set(customerRef, {
        'name': name,
        'phone': phone,
        'shop': activeShop, // 🟢 අලුත් customer කෙනෙක් නම් shop එක save වෙනවා
        'total_debt': FieldValue.increment(widget.totalAmount),
        'last_order_amount': widget.totalAmount,
        'total_profit_accumulated': FieldValue.increment(transactionProfit),
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      DocumentReference historyRef = customerRef.collection('history').doc();
      batch.set(historyRef, {
        'items': widget.cartItems,
        'amount': widget.totalAmount,
        'profit_earned': transactionProfit,
        'shop': activeShop, // 🟢 History එකටත් shop එක දැම්මා
        'date': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
        'status': 'NOT PAID',
        'type': 'ORDER',
      });

      // 🔔 Notification යවන කොටස
      DocumentReference notifyRef = FirebaseFirestore.instance
          .collection('notifications')
          .doc();
      batch.set(notifyRef, {
        'type': 'credit_order',
        'name': name,
        'last_order_amount': widget.totalAmount,
        'shop': activeShop, // 🟢 මෙතනට දැන් customer ගේ shop එක වැටෙනවා
        'timestamp': FieldValue.serverTimestamp(),
        'imageUrl': '',
      });

      await batch.commit();
      if (_sendWhatsAppCheck)
        _sendWhatsAppNotification(phone, name, widget.totalAmount, activeShop);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _sendWhatsAppNotification(
    String phone,
    String name,
    double amount,
    String shopName,
  ) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!cleanPhone.startsWith('39')) cleanPhone = "39$cleanPhone";

    // 🟢 WhatsApp පණිවිඩයටත් Shop එකේ නම එකතු කළා
    String msg =
        "Gentile $name,\nTi informiamo che un importo di *€${amount.toStringAsFixed(2)}* è stato aggiunto al tuo conto credito presso *$shopName*. 🇱🇰 *$shopName* ආයතනයේ ඔබගේ ණය ගිණුමට *€${amount.toStringAsFixed(2)}* ක මුදලක් ඇතුළත් කරන ලදී. ස්තූතියි!";

    final Uri url = Uri.parse(
      "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(msg)}",
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("WhatsApp error");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Select Credit Customer",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isSaving
          ? Center(child: CircularProgressIndicator(color: primaryGreen))
          : Column(
              children: [
                _buildTotalHeader(),
                _buildSearchField(),
                _buildCustomerList(),
              ],
            ),
    );
  }

  Widget _buildTotalHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: primaryGreen,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Order Total:",
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          Text(
            "€${widget.totalAmount.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        // නම සහ අංකය දෙකම search කිරීමට keyboard type එක text කළා
        keyboardType: TextInputType.text,
        onChanged: (v) => setState(() {}),
        decoration: InputDecoration(
          hintText: "Search Name or Phone Number...",
          prefixIcon: Icon(Icons.search, color: primaryGreen),
          filled: true,
          fillColor: primaryGreen.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerList() {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('customers').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          String query = _searchController.text.toLowerCase();

          var docs = snapshot.data!.docs.where((d) {
            var data = d.data() as Map<String, dynamic>;
            String name = (data['name'] ?? "").toString().toLowerCase();
            String phone = (data['phone'] ?? "").toString();

            // 🟢 Name එකෙන් හෝ Phone එකෙන් Search කළ හැකියි
            return name.contains(query) || phone.contains(query);
          }).toList();

          // Search එකේ ප්‍රතිඵල නැත්නම් සහ අංකයක් (Phone) search කරන බව පෙනේ නම් පමණක් අලුත් form එක පෙන්වයි
          if (docs.isEmpty &&
              _searchController.text.length > 5 &&
              RegExp(r'^[0-9]+$').hasMatch(_searchController.text))
            return _buildNewCustomerForm();

          if (docs.isEmpty)
            return const Center(child: Text("No customers found."));

          return ListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemBuilder: (context, i) {
              var data = docs[i].data() as Map<String, dynamic>;
              double debt =
                  double.tryParse(data['total_debt']?.toString() ?? "0") ?? 0.0;
              String shop = data['shop'] ?? "";

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: primaryGreen,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    data['name'] ?? "No Name",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "${data['phone'] ?? ""} ${shop.isNotEmpty ? "• $shop" : ""}",
                  ),
                  trailing: Text(
                    "€${debt.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => _confirmCreditOrder(data, docs[i].id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNewCustomerForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          Icon(Icons.person_add_alt_1, size: 60, color: primaryGreen),
          const SizedBox(height: 10),
          const Text(
            "New Customer Found!",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: "Full Name",
              prefixIcon: Icon(Icons.person, color: primaryGreen),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 🟢 Shop Selection Part
          const Text(
            "Select Customer Shop",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text("Cassia"),
                selected: _selectedShopForNewCustomer == "Cassia",
                onSelected: (val) {
                  setState(
                    () => _selectedShopForNewCustomer = val ? "Cassia" : "",
                  );
                },
              ),
              const SizedBox(width: 15),
              ChoiceChip(
                label: const Text("Battistini"),
                selected: _selectedShopForNewCustomer == "Battistini",
                onSelected: (val) {
                  setState(
                    () => _selectedShopForNewCustomer = val ? "Battistini" : "",
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (_nameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter customer name")),
                  );
                  return;
                }
                if (_selectedShopForNewCustomer.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please select a shop")),
                  );
                  return;
                }

                _confirmCreditOrder({
                  'name': _nameController.text,
                  'phone': _searchController.text,
                  'total_debt': 0,
                  'credit_limit': 50,
                  'shop':
                      _selectedShopForNewCustomer, // 🟢 තේරූ Shop එක Firestore යැවීම
                }, _searchController.text);
              },
              child: const Text(
                "Record New User",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
