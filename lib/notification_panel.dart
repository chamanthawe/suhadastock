import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationPanel extends StatelessWidget {
  const NotificationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // සදාහරිත තද කොළ පැහැය සහ වර්ණ සංකලනය
    final Color primaryGreen = const Color(0xFF1B5E20);
    final Color secondaryGreen = const Color(0xFF2E7D32);
    final Color accentOrange = const Color(0xFFFF8F00);
    final Color creditRed = const Color(0xFFD32F2F);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F1), // ලා කොළ/සුදු පසුබිම
      appBar: AppBar(
        title: const Text(
          "Notifications",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryGreen, secondaryGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 28),
            onPressed: () => _clearAllNotifications(context),
            tooltip: "Clear All",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: primaryGreen),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 100,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "All caught up!",
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

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;

              // Notification වර්ගය හඳුනාගැනීම
              bool isCredit = data['type'] == 'credit_order';

              DateTime? date = (data['timestamp'] as Timestamp?)?.toDate();
              String timeStr = date != null
                  ? DateFormat('hh:mm a').format(date)
                  : "";
              String dateStr = date != null
                  ? DateFormat('MMM dd, yyyy').format(date)
                  : "";

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) => doc.reference.delete(),
                background: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.only(right: 20),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          // වම් පැත්තේ ඇති පාට තීරුව
                          Container(
                            width: 6,
                            color: isCredit ? creditRed : accentOrange,
                          ),

                          // Image හෝ Icon Section
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey[50],
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                ),
                              ),
                              child:
                                  data['imageUrl'] != null &&
                                      data['imageUrl'] != ""
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: data['imageUrl'],
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) =>
                                            Icon(
                                              isCredit
                                                  ? Icons.person
                                                  : Icons.inventory,
                                              color: isCredit
                                                  ? creditRed
                                                  : primaryGreen,
                                            ),
                                      ),
                                    )
                                  : Icon(
                                      isCredit
                                          ? Icons.person
                                          : Icons.inventory_2_rounded,
                                      color: isCredit
                                          ? creditRed
                                          : primaryGreen,
                                      size: 30,
                                    ),
                            ),
                          ),

                          // විස්තර Section
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Customer Name (Credit නම්) හෝ Product Name
                                  Text(
                                    data['productName'] ?? "Unknown",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isCredit
                                          ? creditRed
                                          : primaryGreen,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCredit
                                              ? Colors.red[50]
                                              : Colors.orange[50],
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          isCredit
                                              ? "Total: €${data['value'] ?? '0.00'}"
                                              : "Stock: ${data['remainingStock'] ?? '0'}",
                                          style: TextStyle(
                                            color: isCredit
                                                ? creditRed
                                                : Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        "|  ${data['shop'] ?? ''}",
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Date සහ Time
                                  Text(
                                    "$dateStr at $timeStr",
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ඉවත් කිරීමේ Button එක
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: Colors.grey[300],
                              size: 20,
                            ),
                            onPressed: () => doc.reference.delete(),
                          ),
                        ],
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

  void _clearAllNotifications(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear All"),
        content: const Text(
          "Are you sure you want to delete all notifications?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              var collection = FirebaseFirestore.instance.collection(
                'notifications',
              );
              var snapshots = await collection.get();
              for (var doc in snapshots.docs) {
                await doc.reference.delete();
              }
            },
            child: const Text(
              "Delete All",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
