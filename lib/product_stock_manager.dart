import 'package:cloud_firestore/cloud_firestore.dart';

class ProductStockManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> processStockUpdate({
    required Map<String, dynamic> item,
    required String branch,
    required String baseUrl,
    required String ck,
    required String cs,
  }) async {
    try {
      String productId = item['id'].toString();
      String stockKey = '${branch.toLowerCase()}_stock';

      // ✅ නම වෙනස් කළා: is_weighted
      bool isWeighted = item['is_weighted'] ?? false;

      dynamic quantityToSubtract;

      if (isWeighted) {
        // බර කිරන බඩු නම් දශම සහිතව (Double)
        quantityToSubtract = (item['qty'] as num).toDouble();
      } else {
        // සාමාන්‍ය බඩු නම් පූර්ණ සංඛ්‍යාවක් (Integer) - එවිට දශම වැටෙන්නේ නැත
        quantityToSubtract = (item['qty'] as num).toInt();
      }

      // Firestore Update
      await _firestore.collection('products_data').doc(productId).update({
        stockKey: FieldValue.increment(-quantityToSubtract),
        'last_updated': FieldValue.serverTimestamp(),
      });

      // WooCommerce Sync
      if (!isWeighted) {
        // සාමාන්‍ය බඩු පමණක් පූර්ණ සංඛ්‍යාවෙන් Sync කරයි
        await _syncToWoo(productId, quantityToSubtract, baseUrl, ck, cs);
      } else {
        print("Skipped Woo Sync for Weighted Product: ${item['name']}");
      }
    } catch (e) {
      print("Error updating stock: $e");
    }
  }

  Future<void> _syncToWoo(
    String id,
    int qty,
    String url,
    String ck,
    String cs,
  ) async {
    // WooCommerce API logic here
  }
}
