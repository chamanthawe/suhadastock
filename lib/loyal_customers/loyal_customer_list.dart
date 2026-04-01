import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'loyal_customer_profile.dart';

class LoyalCustomerList extends StatelessWidget {
  const LoyalCustomerList({super.key});

  @override
  Widget build(BuildContext context) {
    // Colors
    final Color primaryGreen = Colors.green.shade800;
    final Color accentGreen = Colors.green.shade600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5), // Soft Greenish Grey background
      appBar: AppBar(
        title: const Text(
          "Loyal Business Partners",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
        backgroundColor: primaryGreen,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryGreen,
        elevation: 4,
        icon: const Icon(Icons.add_moderator, color: Colors.white),
        label: const Text(
          "NEW PARTNER",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (c) => const LoyalCustomerProfile()),
        ),
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('loyal_customers')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: primaryGreen),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];

              // --- Error Fix Logic Start ---
              // Firestore එකෙන් data ගන්නකොට map එකක් විදිහට අරගෙන default values දෙන එක තමයි ආරක්ෂිතම ක්‍රමය.
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              bool isBusiness = data.containsKey('special_for_business')
                  ? data['special_for_business']
                  : false;
              String name = data.containsKey('name') ? data['name'] : 'No Name';
              String surname = data.containsKey('surname')
                  ? data['surname']
                  : '';
              String phone = data.containsKey('phone')
                  ? data['phone']
                  : 'No Phone';
              String shopName = data.containsKey('shop')
                  ? data['shop']
                  : 'No Shop';
              // --- Error Fix Logic End ---

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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => LoyalCustomerProfile(
                            customerId: doc.id,
                            existingData: data,
                          ),
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      leading: _buildLeadingAvatar(shopName, primaryGreen),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "$name $surname",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF2C3E50),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBusiness)
                            const Tooltip(
                              message: "Verified Business",
                              child: Icon(
                                Icons.verified,
                                size: 18,
                                color: Colors.blue,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 5),
                          _infoRow(
                            Icons.phone_iphone,
                            phone,
                            Colors.grey.shade600,
                          ),
                          const SizedBox(height: 4),
                          _infoRow(Icons.location_on, shopName, accentGreen),
                        ],
                      ),
                      trailing: CircleAvatar(
                        backgroundColor: Colors.green.shade50,
                        radius: 18,
                        child: Icon(
                          Icons.arrow_forward_ios,
                          color: primaryGreen,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLeadingAvatar(String shop, Color primary) {
    bool isCassia = shop.toLowerCase() == "cassia";
    return Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCassia
              ? [Colors.green.shade400, Colors.green.shade700]
              : [Colors.teal.shade300, Colors.teal.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isCassia ? Colors.green : Colors.teal).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          shop.isNotEmpty ? shop[0].toUpperCase() : "?",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.green.shade200,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "No Partners Found",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const Text(
            "Click the button below to add your first loyal partner.",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
