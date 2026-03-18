import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

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

  // Green Theme Colors
  final Color primaryGreen = const Color(0xFF1B5E20);
  final Color accentGreen = const Color(0xFF2E7D32);

  double _calculateTransactionProfit() {
    double totalProfit = 0;
    for (var item in widget.cartItems) {
      // මෙතන profit එක item එක ඇතුලේ තියෙන key එක අනුව හරියටම ගන්න
      double p = double.tryParse(item['profit']?.toString() ?? "0") ?? 0.0;
      double q = double.tryParse(item['qty']?.toString() ?? "1") ?? 1.0;
      totalProfit += (p * q);
    }
    return totalProfit;
  }

  void _confirmCreditOrder(Map<String, dynamic> customerData, String docId) {
    String name = customerData['name'] ?? "Unknown";
    String phone = customerData['phone'] ?? "";

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
              const SizedBox(height: 5),
              Text(
                "Total Amount: €${widget.totalAmount.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isOverLimit ? Colors.red : primaryGreen,
                ),
              ),
              if (isOverLimit) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "This customer has reached their credit limit of €${limit.toStringAsFixed(2)}.",
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const Divider(height: 30),
              AbsorbPointer(
                absorbing: isOverLimit,
                child: Opacity(
                  opacity: isOverLimit ? 0.5 : 1.0,
                  child: SwitchListTile(
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
                ),
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
                  _processCreditOrder(docId, name, phone);
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
  ) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    double transactionProfit = _calculateTransactionProfit();

    try {
      // 1. Update Customer Record
      await FirebaseFirestore.instance.collection('customers').doc(docId).set({
        'name': name,
        'phone': phone,
        'total_debt': FieldValue.increment(widget.totalAmount),
        'last_order_amount': widget.totalAmount,
        'total_profit_accumulated': FieldValue.increment(transactionProfit),
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Add to History
      await FirebaseFirestore.instance
          .collection('customers')
          .doc(docId)
          .collection('history')
          .add({
            'items': widget.cartItems,
            'amount': widget.totalAmount,
            'profit_earned': transactionProfit,
            'date': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
            'status': 'NOT PAID',
            'type': 'ORDER',
          });

      // 3. --- NEW: Send Notification to Notification Panel ---
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'credit_order',
        'productName': 'Credit Order: $name', // Notification එකේ පෙන්නන නම
        'remainingStock': widget.totalAmount.toStringAsFixed(
          2,
        ), // මුදල පෙන්වීමට මෙය භාවිතා කරයි
        'shop': 'Branch Name', // මෙතනට ඔයාගේ branch එකේ නම pass කරන්න පුළුවන්
        'imageUrl':
            'https://cdn-icons-png.flaticon.com/512/951/951764.png', // Credit icon url
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'customer': name,
      });

      if (_sendWhatsAppCheck) {
        _sendWhatsAppNotification(phone, name, widget.totalAmount);
      }

      // 4. Return success and customer name back to OrderScreen
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
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
  ) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!cleanPhone.startsWith('39')) cleanPhone = "39$cleanPhone";

    String msg =
        """
Gentile $name,
Ti informiamo che un importo di *€${amount.toStringAsFixed(2)}* è stato aggiunto al tuo conto credito. 🇱🇰 ඔබගේ ණය ගිණුමට *€${amount.toStringAsFixed(2)}* ක මුදලක් ඇතුළත් කරන ලදී. ස්තූතියි!
""";

    final String url =
        "whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(msg)}";
    final Uri whatsappUri = Uri.parse(url);

    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri);
      } else {
        await launchUrl(
          Uri.parse(
            "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(msg)}",
          ),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint("WhatsApp Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // build method එකේ ඉතිරි කොටස ඔයා දුන්න එකමයි, කිසිම වෙනසක් කළේ නැහැ...
    // (ඉඩ ඉතිරි කර ගැනීමට මෙතනින් පහළ කොටස කෙටි කළා)
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Credit Customer"),
        backgroundColor: primaryGreen,
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTotalHeader(),
                _buildSearchField(),
                _buildCustomerList(),
              ],
            ),
    );
  }

  // Header සහ Search build කරන methods ටික (ඔයාගේ කලින් code එකමයි)
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
        keyboardType: TextInputType.phone,
        onChanged: (v) => setState(() {}),
        decoration: InputDecoration(
          hintText: "Enter Phone Number...",
          prefixIcon: Icon(Icons.search, color: primaryGreen),
          filled: true,
          fillColor: primaryGreen.withValues(alpha: 0.05),
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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data!.docs.where((d) {
            var data = d.data() as Map<String, dynamic>;
            return (data['phone'] ?? "").toString().contains(
              _searchController.text,
            );
          }).toList();

          if (docs.isEmpty && _searchController.text.length > 5) {
            return _buildNewCustomerForm();
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              var data = docs[i].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(data['name'] ?? "No Name"),
                  subtitle: Text(data['phone'] ?? ""),
                  trailing: Text(
                    "€${(double.tryParse(data['total_debt'].toString()) ?? 0).toStringAsFixed(2)}",
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
          const Text(
            "New Customer Found!",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: "Full Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (_nameController.text.isNotEmpty) {
                _confirmCreditOrder({
                  'name': _nameController.text,
                  'phone': _searchController.text,
                  'total_debt': 0,
                  'credit_limit': 50,
                }, _searchController.text);
              }
            },
            child: const Text("Record New User"),
          ),
        ],
      ),
    );
  }
}
