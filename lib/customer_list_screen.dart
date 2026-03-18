import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'customer_profile_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final TextEditingController _searchController = TextEditingController();

  void _sendReminder(String phone, String name, double debt) async {
    if (debt <= 0) return;
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!cleanPhone.startsWith('39')) cleanPhone = "39$cleanPhone";

    String debtStr = debt.toStringAsFixed(2);
    String message =
        "Gentile $name,\n\n" "🇮🇹 Ti inviamo un cordiale promemoria da *Suhada S.R.L.S.* Il tuo saldo in sospeso è di *€$debtStr*. Ti preghiamo gentilmente di regolarizzarlo appena possibile. Grazie! 🙏\n\n" "🇱🇰 *Suhada S.R.L.S.* ආයතනයෙන් කෙරෙන කාරුණික සිහිපත් කිරීමකි. ඔබ ගෙවීමට ඇති ඉතිරි මුදල වන *€$debtStr* පියවන ලෙස කාරුණිකව ඉල්ලා සිටිමු. ස්තූතියි! 🙏\n\n" "__________________________\n" "🤖 *Messaggio Automatico / මෙය ස්වයංක්‍රීයව ලැබෙන පණිවිඩයකි.*";

    final Uri whatsappUri = Uri.parse(
      "whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(message)}",
    );
    try {
      bool launched = await launchUrl(whatsappUri);
      if (!launched) {
        await launchUrl(
          Uri.parse(
            "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}",
          ),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  void _showCustomerForm({
    String? id,
    String? currentName,
    String? currentPhone,
  }) {
    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: currentPhone);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text(id == null ? "New Customer" : "Update Customer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: "Full Name",
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: phoneController,
              decoration: InputDecoration(
                labelText: "Phone Number",
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              keyboardType: TextInputType.phone,
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                if (id == null) {
                  await FirebaseFirestore.instance.collection('customers').add({
                    'name': nameController.text,
                    'phone': phoneController.text,
                    'total_debt': 0.0,
                    'created_at': FieldValue.serverTimestamp(),
                  });
                } else {
                  await FirebaseFirestore.instance
                      .collection('customers')
                      .doc(id)
                      .update({
                        'name': nameController.text,
                        'phone': phoneController.text,
                      });
                }
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          "SUHADA S.R.L.S",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1B5E20),
        onPressed: () => _showCustomerForm(),
        icon: const Icon(Icons.add_reaction_outlined, color: Colors.white),
        label: const Text(
          "Add Customer",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: "Search customer name...",
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Color(0xFF1B5E20),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 15),
                ),
                onChanged: (v) => setState(() {}),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // 🔴 orderBy අයින් කළා. මොකද created_at නැති අය පේන්නේ නැති වෙන නිසා.
              // ඒ වෙනුවට raw stream එක අරගෙන App එක ඇතුළේදී sort කරනවා.
              stream: FirebaseFirestore.instance
                  .collection('customers')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Error loading data"));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // දත්ත සියල්ලම List එකකට ගන්නවා
                var docs = snapshot.data!.docs;

                // Search filtering
                var filteredDocs = docs.where((d) {
                  var data = d.data() as Map<String, dynamic>;
                  String name = (data['name'] ?? "").toString().toLowerCase();
                  return name.contains(_searchController.text.toLowerCase());
                }).toList();

                // 🟢 අකුරු පිළිවෙලට (A-Z) Sort කිරීම
                filteredDocs.sort((a, b) {
                  String nameA =
                      (a.data() as Map<String, dynamic>)['name']
                          ?.toString()
                          .toLowerCase() ??
                      "";
                  String nameB =
                      (b.data() as Map<String, dynamic>)['name']
                          ?.toString()
                          .toLowerCase() ??
                      "";
                  return nameA.compareTo(nameB);
                });

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No customers found.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, i) {
                    var data = filteredDocs[i].data() as Map<String, dynamic>;
                    double debt =
                        double.tryParse(
                          data['total_debt']?.toString() ?? "0",
                        ) ??
                        0.0;
                    String name = data['name'] ?? "Unknown";
                    String phone = data['phone'] ?? "No Phone";

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: ListTile(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CustomerProfileScreen(
                              customerId: filteredDocs[i].id,
                            ),
                          ),
                        ),
                        onLongPress: () => _showCustomerForm(
                          id: filteredDocs[i].id,
                          currentName: name,
                          currentPhone: phone,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[700],
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : "?",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(phone),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "€${debt.toStringAsFixed(2)}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: debt > 0
                                        ? Colors.red
                                        : Colors.green[700],
                                  ),
                                ),
                                Text(
                                  debt > 0 ? "PENDING" : "CLEAR",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: debt > 0 ? Colors.red : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(
                                Icons.send_rounded,
                                color: Colors.green,
                              ),
                              onPressed: () => _sendReminder(phone, name, debt),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('customers').snapshots(),
      builder: (context, snapshot) {
        double totalDebt = 0;
        int customerCount = 0;
        if (snapshot.hasData) {
          customerCount = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            totalDebt +=
                double.tryParse(data['total_debt']?.toString() ?? "0") ?? 0.0;
          }
        }
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.all(15),
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
            ),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Column(
            children: [
              const Text(
                "TOTAL OUTSTANDING",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "€${totalDebt.toStringAsFixed(2)}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 35,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "$customerCount Customers",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
