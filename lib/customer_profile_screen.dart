import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerProfileScreen extends StatefulWidget {
  final String customerId;

  const CustomerProfileScreen({super.key, required this.customerId});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final TextEditingController _paymentController = TextEditingController();
  final TextEditingController _limitController = TextEditingController();

  // WhatsApp පණිවිඩය යැවීම
  Future<void> _sendWhatsAppMessage(String phone, String message) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!cleanPhone.startsWith('39')) cleanPhone = "39$cleanPhone";

    final String whatsappScheme =
        "whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(message)}";
    final Uri url = Uri.parse(whatsappScheme);

    try {
      bool launched = await launchUrl(url);
      if (!launched) {
        final Uri webUrl = Uri.parse(
          "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}",
        );
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("WhatsApp Error: $e");
    }
  }

  // 🟢 Credit Limit එක සහ Shop එක එකවර Update කරන Function එක
  Future<void> _updateCustomerSettings(double newLimit, String newShop) async {
    try {
      await FirebaseFirestore.instance
          .collection('customers')
          .doc(widget.customerId)
          .update({
            'credit_limit': newLimit,
            'shop': newShop, // Firestore එකේ Save කිරීම
          });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Settings updated: Limit €${newLimit.toStringAsFixed(2)} | Shop: $newShop",
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Update Error: $e");
    }
  }

  // 🟢 Settings (Limit & Shop) Edit Dialog එක
  void _showLimitEditDialog(double currentLimit, String currentShop) {
    _limitController.text = currentLimit.toStringAsFixed(2);
    String selectedShop = currentShop.isEmpty ? "Cassia" : currentShop;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Customer Settings",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select Shop",
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
                    selected: selectedShop == "Cassia",
                    onSelected: (val) {
                      if (val) setDialogState(() => selectedShop = "Cassia");
                    },
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text("Battistini"),
                    selected: selectedShop == "Battistini",
                    onSelected: (val) {
                      if (val)
                        setDialogState(() => selectedShop = "Battistini");
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "Credit Limit",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _limitController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  prefixText: "€ ",
                  labelText: "Max Credit Allowed",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
              ),
              onPressed: () {
                double? val = double.tryParse(_limitController.text);
                if (val != null) {
                  _updateCustomerSettings(val, selectedShop);
                }
              },
              child: const Text(
                "Save Changes",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Order Details Dialog
  void _showOrderDetails(Map<String, dynamic> historyData) {
    List items = historyData['items'] ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text(
          "🛒 Order Items",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: items.isEmpty
              ? const Text("No item details found.")
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    var item = items[index];
                    String name = (item['name'] ?? "Unknown Item").toString();
                    double price =
                        double.tryParse(item['price']?.toString() ?? "0.0") ??
                        0.0;
                    int qty =
                        int.tryParse(item['quantity']?.toString() ?? "1") ?? 1;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "Qty: $qty x €${price.toStringAsFixed(2)}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "€${(price * qty).toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // මුදල් ගෙවීම සහ WhatsApp යැවීම
  Future<void> _processPayment(
    Map<String, dynamic> customerData,
    double payAmount,
  ) async {
    // 1. අවශ්‍ය මූලික දත්ත ලබා ගැනීම
    double currentDebt =
        double.tryParse(customerData['total_debt']?.toString() ?? "0") ?? 0.0;

    // 🔥 Floating Point Issue එක මෙතැනදී Fix කරන ලදී
    double newDebt = double.parse((currentDebt - payAmount).toStringAsFixed(2));

    String shop = customerData['shop'] ?? 'Unassigned';
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String reportDocId = "${shop}_$today";

    try {
      // References සාදා ගැනීම
      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('customers')
          .doc(widget.customerId);
      DocumentReference dailyReportRef = FirebaseFirestore.instance
          .collection('daily_reports')
          .doc(reportDocId);

      // --- 🔥 Transaction එක නිවැරදි පිළිවෙළට (Reads before Writes) ---
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // පියවර 1: සියලුම READS (get) මෙතැනදී සිදු කළ යුතුයි
        DocumentSnapshot dailySnap = await transaction.get(dailyReportRef);

        // පියවර 2: සියලුම WRITES (update/set) මෙතැන් සිට සිදු කළ යුතුයි

        // Customer ගේ ණය මුදල update කිරීම
        transaction.update(customerRef, {
          'total_debt': newDebt, // දැන් මෙතනට යන්නේ දශමස්ථාන 2ක අගයකි
          'last_payment_date': FieldValue.serverTimestamp(),
        });

        // Daily Report එක Update කිරීම
        if (!dailySnap.exists) {
          transaction.set(dailyReportRef, {
            'total_customer_payments': payAmount,
            'shop': shop,
            'date': today,
            'last_updated': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(dailyReportRef, {
            'total_customer_payments': FieldValue.increment(payAmount),
            'last_updated': FieldValue.serverTimestamp(),
          });
        }
      });

      // 3. History එකට එකතු කිරීම (Transaction එකෙන් පිටත කළ හැක)
      await customerRef.collection('history').add({
        'type': 'PAYMENT',
        'amount_paid': payAmount,
        'remaining_balance': newDebt,
        'date': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      });

      // 4. Notification Panel එකට Alert එක යැවීම
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'payment_received',
        'name': customerData['name'] ?? 'Unknown Customer',
        'amount': payAmount.toStringAsFixed(2),
        'remaining': newDebt.toStringAsFixed(2),
        'shop': shop,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // WhatsApp පණිවිඩය සකස් කිරීම
      String msg =
          """
✅ CONFERMA DI PAGAMENTO

Gentile ${customerData['name'] ?? 'Cliente'},
🇮🇹 Abbiamo ricevuto il tuo pagamento di €${payAmount.toStringAsFixed(2)}. Il tuo debito rimanente è di €${newDebt.toStringAsFixed(2)}. 

🇱🇰 ඔබගේ €${payAmount.toStringAsFixed(2)} ක ගෙවීම අප වෙත ලැබී ඇත. ඔබ ගෙවීමට ඇති ඉතිරි මුදල €${newDebt.toStringAsFixed(2)} වේ. 

🙏 Grazie per aver scelto Suhada S.R.L.S.!

__
🤖 Messaggio Automatico
""";

      if (mounted) {
        Navigator.pop(context); // Dialog එක වසන්න
        _paymentController.clear();
        await _sendWhatsAppMessage(customerData['phone'] ?? "", msg);
      }
    } catch (e) {
      debugPrint("Update Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error processing payment: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('customers')
          .doc(widget.customerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        var userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        double totalDebt =
            double.tryParse(userData['total_debt']?.toString() ?? "0") ?? 0.0;
        double creditLimit =
            double.tryParse(userData['credit_limit']?.toString() ?? "50.0") ??
            50.0;
        String name = userData['name'] ?? "Customer Profile";
        String currentShop = userData['shop'] ?? ""; // පවතින Shop එක

        return Scaffold(
          backgroundColor: Colors.grey[100],
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 180.0,
                pinned: true,
                backgroundColor: const Color(0xFF1B5E20),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.settings_suggest,
                      color: Colors.white,
                    ),
                    onPressed: () =>
                        _showLimitEditDialog(creditLimit, currentShop),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        CircleAvatar(
                          radius: 35,
                          backgroundColor: Colors.white24,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : "?",
                            style: const TextStyle(
                              fontSize: 32,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${userData['phone'] ?? ""} ${currentShop.isNotEmpty ? "• $currentShop" : ""}",
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "TOTAL PENDING BALANCE",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "€${totalDebt.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: totalDebt > 0
                              ? Colors.redAccent
                              : Colors.green[700],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Credit Limit: €${creditLimit.toStringAsFixed(2)}",
                          style: TextStyle(
                            color: totalDebt >= creditLimit
                                ? Colors.red
                                : Colors.grey,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showPaymentDialog(userData),
                          icon: const Icon(Icons.add_card_rounded),
                          label: const Text(
                            "RECORD PAYMENT",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                  child: Text(
                    "TRANSACTION HISTORY",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('customers')
                    .doc(widget.customerId)
                    .collection('history')
                    .orderBy('date', descending: true)
                    .snapshots(),
                builder: (context, hSnapshot) {
                  if (!hSnapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      var history =
                          hSnapshot.data!.docs[i].data()
                              as Map<String, dynamic>;
                      bool isPayment = history['type'] == 'PAYMENT';

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ListTile(
                          onTap: isPayment
                              ? null
                              : () => _showOrderDetails(history),
                          leading: CircleAvatar(
                            backgroundColor: isPayment
                                ? Colors.green[50]
                                : Colors.red[50],
                            child: Icon(
                              isPayment
                                  ? Icons.check_circle_rounded
                                  : Icons.shopping_bag_outlined,
                              color: isPayment ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Text(
                            isPayment ? "Payment Received" : "Purchase Order",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            history['date'] ?? "",
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Text(
                            "${isPayment ? '-' : '+'} €${(isPayment ? (history['amount_paid'] ?? 0) : (history['amount'] ?? 0)).toDouble().toStringAsFixed(2)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isPayment ? Colors.green[700] : Colors.red,
                            ),
                          ),
                        ),
                      );
                    }, childCount: hSnapshot.data!.docs.length),
                  );
                },
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 30)),
            ],
          ),
        );
      },
    );
  }

  void _showPaymentDialog(Map<String, dynamic> userData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text(
          "Record Payment",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter the amount paid by the customer",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _paymentController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: "€ ",
                hintText: "0.00",
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
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
          ElevatedButton(
            onPressed: () {
              double? amt = double.tryParse(_paymentController.text);
              if (amt != null && amt > 0) _processPayment(userData, amt);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Confirm & Send",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
