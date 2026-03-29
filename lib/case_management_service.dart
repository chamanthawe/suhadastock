import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
// import 'constants.dart'; // ඔයාගේ path එක අනුව තියාගන්න

class CaseManagementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> breakCaseToSingleUnits({
    required String caseProductId,
    required String singleProductId,
    required int itemsPerCase,
    required String branch,
  }) async {
    try {
      final String stockKey = '${branch}_stock';

      // 🛒 1. Firestore එකෙන් Document References ලබා ගැනීම
      final caseRef = _firestore.collection('products_data').doc(caseProductId);
      final singleRef = _firestore
          .collection('products_data')
          .doc(singleProductId);

      // 🔥 2. Transaction එකක් භාවිතා කිරීම වඩාත් ආරක්ෂිතයි (එකවර දෙන්නෙක් කළොත් අවුල් නොවෙන්න)
      return await _firestore.runTransaction((transaction) async {
        final caseDoc = await transaction.get(caseRef);
        final singleDoc = await transaction.get(singleRef);

        if (!caseDoc.exists || !singleDoc.exists) return false;

        // 🔍 3. අගයන් පූර්ණ සංඛ්‍යා (int) ලෙස ලබා ගැනීම
        // num.toInt() භාවිතා කිරීමෙන් double තිබුණත් ඒක int එකක් බවට පත් වෙනවා
        int currentCaseStock = (caseDoc.data()![stockKey] as num? ?? 0).toInt();
        int currentSingleStock = (singleDoc.data()![stockKey] as num? ?? 0)
            .toInt();

        // ✅ Case Stock එක 1 ට වඩා අඩු නම් නවත්වන්න
        if (currentCaseStock < 1) return false;

        // 🧮 4. අලුත් Stock ගණනය කිරීම (අනිවාර්යයෙන්ම int විදිහට)
        int finalCaseStock = currentCaseStock - 1;
        int finalSingleStock = currentSingleStock + itemsPerCase;

        // 🔥 5. Firestore Update (අගයන් int ලෙසම යවනවා)
        transaction.update(caseRef, {
          stockKey: finalCaseStock,
          'last_updated': FieldValue.serverTimestamp(),
        });

        transaction.update(singleRef, {
          stockKey: finalSingleStock,
          'last_updated': FieldValue.serverTimestamp(),
        });

        // ☁️ 6. WooCommerce Sync (පසුබිමින් ක්‍රියාත්මක වේ)
        _syncToWooCommerce(caseProductId, finalCaseStock, branch);
        _syncToWooCommerce(singleProductId, finalSingleStock, branch);

        return true;
      });
    } catch (e) {
      print("Case Break Error: $e");
      return false;
    }
  }

  Future<void> _syncToWooCommerce(
    String productId,
    int newStock, // මෙතනත් int භාවිතා කරන්න
    String branch,
  ) async {
    // සටහන: මෙහි AppConstants වෙනුවට ඔයාගේ code එකේ තියෙන විදිහට baseUrl/ck/cs දාන්න
    final String url =
        "YOUR_BASE_URL/products/$productId?consumer_key=YOUR_CK&consumer_secret=YOUR_CS";

    Map<String, dynamic> body = {
      "meta_data": [
        {"key": "${branch}_stock", "value": newStock.toString()},
      ],
    };

    // Cassia හෝ වෙනත් logic අනුව stock_quantity update කිරීම
    body["manage_stock"] = true;
    body["stock_quantity"] = newStock;

    try {
      await http.put(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );
    } catch (e) {
      print("WooSync Error: $e");
    }
  }
}
