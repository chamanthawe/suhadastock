import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'loyal_customer_profile.dart';

class LoyalCustomerList extends StatefulWidget {
  const LoyalCustomerList({super.key});

  @override
  State<LoyalCustomerList> createState() => _LoyalCustomerListState();
}

class _LoyalCustomerListState extends State<LoyalCustomerList> {
  // Search සහ Filter සඳහා විචල්‍යයන්
  String searchQuery = "";
  String filterType = "All"; // All, Top Spenders, Cassia, Battistini
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // --- Points Manager Dialog ---
  void _showPointsManager(BuildContext context, Color primaryGreen) {
    final TextEditingController earnController = TextEditingController();
    final TextEditingController redeemController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('settings')
            .doc('loyalty_config')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            var config = snapshot.data!.data() as Map<String, dynamic>;
            earnController.text = config['points_per_item']?.toString() ?? "1";
            redeemController.text =
                config['points_to_euro_value']?.toString() ?? "100";
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            title: Row(
              children: [
                Icon(Icons.stars, color: primaryGreen),
                const SizedBox(width: 10),
                const Text(
                  "Points Manager",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "ගනුදෙනුකරුවන්ට Points ලැබෙන සහ ඒවා මුදල් බවට පත් කරන ආකාරය මෙතනින් සකසන්න.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: earnController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Points per 1 Item",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.add_shopping_cart),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: redeemController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Points for €1.00 Discount",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CANCEL"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('settings')
                      .doc('loyalty_config')
                      .set({
                        'points_per_item':
                            int.tryParse(earnController.text) ?? 1,
                        'points_to_euro_value':
                            int.tryParse(redeemController.text) ?? 100,
                        'last_updated': FieldValue.serverTimestamp(),
                      });
                  Navigator.pop(context);
                },
                child: const Text(
                  "SAVE SETTINGS",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryGreen = Colors.green.shade800;
    final Color accentGreen = Colors.green.shade600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        title: !isSearching
            ? const Text(
                "Loyal Customers",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
            : TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Search Name or Phone...",
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) =>
                    setState(() => searchQuery = value.toLowerCase()),
              ),
        centerTitle: true,
        backgroundColor: primaryGreen,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isSearching ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: () => setState(() {
              isSearching = !isSearching;
              if (!isSearching) searchQuery = "";
              _searchController.clear();
            }),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (value) => setState(() => filterType = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: "All", child: Text("All Customers")),
              const PopupMenuItem(
                value: "Top",
                child: Text("Top Spenders (Annual)"),
              ),
              const PopupMenuItem(value: "Cassia", child: Text("Cassia Shop")),
              const PopupMenuItem(
                value: "Battistini",
                child: Text("Battistini Shop"),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_suggest, color: Colors.white),
            onPressed: () => _showPointsManager(context, primaryGreen),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryGreen,
        icon: const Icon(Icons.add_moderator, color: Colors.white),
        label: const Text("NEW PARTNER", style: TextStyle(color: Colors.white)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (c) => const LoyalCustomerProfile()),
        ),
      ),
      body: StreamBuilder(
        stream: _getFilteredStream(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: primaryGreen),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
            return _buildEmptyState();

          // Client-side Searching Logic (Firestore supports limited complex searching)
          var docs = snapshot.data!.docs.where((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            String name = (data['name'] ?? "").toString().toLowerCase();
            String surname = (data['surname'] ?? "").toString().toLowerCase();
            String phone = (data['phone'] ?? "").toString();
            return name.contains(searchQuery) ||
                surname.contains(searchQuery) ||
                phone.contains(searchQuery);
          }).toList();

          if (docs.isEmpty) return _buildEmptyState();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      filterType == "All"
                          ? "REGISTERED CUSTOMERS"
                          : "FILTERED: $filterType",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primaryGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${docs.length} Total",
                        style: TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    Map<String, dynamic> data =
                        doc.data() as Map<String, dynamic>;

                    // UI දත්ත ලබා ගැනීම
                    String name = data['name'] ?? 'No Name';
                    String surname = data['surname'] ?? '';
                    String phone = data['phone'] ?? 'No Phone';
                    String shopName = data['shop'] ?? 'No Shop';
                    int points = data['points'] ?? 0;
                    double annualSpent = (data['total_spent_annual'] ?? 0.0)
                        .toDouble();

                    return _buildCustomerCard(
                      doc.id,
                      data,
                      name,
                      surname,
                      phone,
                      shopName,
                      points,
                      annualSpent,
                      primaryGreen,
                      accentGreen,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Filter එක අනුව Stream එක වෙනස් කරන function එක
  Stream<QuerySnapshot> _getFilteredStream() {
    Query query = FirebaseFirestore.instance.collection('loyal_customers');

    if (filterType == "Top") {
      return query.orderBy('total_spent_annual', descending: true).snapshots();
    } else if (filterType == "Cassia") {
      return query.where('shop', isEqualTo: 'Cassia').snapshots();
    } else if (filterType == "Battistini") {
      return query.where('shop', isEqualTo: 'Battistini').snapshots();
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  Widget _buildCustomerCard(
    String id,
    Map<String, dynamic> data,
    String name,
    String surname,
    String phone,
    String shop,
    int pts,
    double spent,
    Color primary,
    Color accent,
  ) {
    bool isBusiness = data['special_for_business'] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) =>
                LoyalCustomerProfile(customerId: id, existingData: data),
          ),
        ),
        contentPadding: const EdgeInsets.all(12),
        leading: _buildLeadingAvatar(name, surname, shop, primary),
        title: Row(
          children: [
            Expanded(
              child: Text(
                "$name $surname",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (isBusiness)
              const Icon(Icons.verified, size: 18, color: Colors.blue),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Row(
              children: [
                _infoRow(Icons.phone_iphone, phone, Colors.grey.shade600),
                const SizedBox(width: 15),
                _pointsBadge(pts),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _infoRow(Icons.location_on, shop, accent),
                Text(
                  "Annual: €${spent.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          radius: 18,
          child: Icon(Icons.arrow_forward_ios, color: primary, size: 14),
        ),
      ),
    );
  }

  Widget _pointsBadge(int pts) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.stars, size: 12, color: Colors.orange),
          const SizedBox(width: 4),
          Text(
            "$pts Pts",
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadingAvatar(
    String name,
    String surname,
    String shop,
    Color primary,
  ) {
    bool isCassia = shop.toLowerCase() == "cassia";
    String initials =
        (name.isNotEmpty ? name[0] : "") +
        (surname.isNotEmpty ? surname[0] : "");
    return Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCassia
              ? [Colors.green.shade400, Colors.green.shade700]
              : [Colors.teal.shade300, Colors.teal.shade600],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.green.shade200),
          const SizedBox(height: 20),
          const Text(
            "No Partners Found",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
