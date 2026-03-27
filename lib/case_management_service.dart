import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

class CaseManagementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> breakCaseToSingleUnits({
    required String caseProductId,
    required String singleProductId,
    required int itemsPerCase,
    required String branch, // 'cassia' හෝ 'battistini'
  }) async {
    try {
      final String stockKey = '${branch}_stock';

      // 🛒 1. Firestore එකෙන් Case සහ Single Product දෙකේම දත්ත කියවීම
      final caseDoc = await _firestore
          .collection('products_data')
          .doc(caseProductId)
          .get();
      final singleDoc = await _firestore
          .collection('products_data')
          .doc(singleProductId)
          .get();

      if (!caseDoc.exists || !singleDoc.exists) return false;

      // 🔍 2. WooCommerce එකෙන් නෙවෙයි, Firestore එකෙන්ම කෙලින්ම Stock එක කියවීම
      double currentCaseStock =
          double.tryParse(caseDoc.data()![stockKey]?.toString() ?? '0') ?? 0.0;
      double currentSingleStock =
          double.tryParse(singleDoc.data()![stockKey]?.toString() ?? '0') ??
          0.0;

      // ✅ අදාළ කඩේ Case Stock එක 1 ට වඩා අඩු නම් Break කරන්න දෙන්නේ නැත
      if (currentCaseStock < 1.0) return false;

      // 🧮 3. අලුත් Stock ගණනය කිරීම
      double finalCaseStock = currentCaseStock - 1.0;
      double finalSingleStock = currentSingleStock + itemsPerCase;

      // 🔥 4. Firestore Live Update
      await _firestore.collection('products_data').doc(caseProductId).update({
        stockKey: finalCaseStock,
      });

      await _firestore.collection('products_data').doc(singleProductId).update({
        stockKey: finalSingleStock,
      });

      // ☁️ 5. WooCommerce Sync (WooCommerce වල තියෙන meta data අප්ඩේට් කිරීම)
      await _syncToWooCommerce(caseProductId, finalCaseStock, branch);
      await _syncToWooCommerce(singleProductId, finalSingleStock, branch);

      return true;
    } catch (e) {
      print("Case Break Error: $e");
      return false;
    }
  }

  Future<void> _syncToWooCommerce(
    String productId,
    double newStock,
    String branch,
  ) async {
    final String url =
        "${AppConstants.baseUrl}/products/$productId?consumer_key=${AppConstants.ck}&consumer_secret=${AppConstants.cs}";

    Map<String, dynamic> body = {
      "meta_data": [
        {"key": "${branch}_stock", "value": newStock.toString()},
      ],
    };

    if (branch == 'cassia') {
      body["stock_quantity"] = newStock
          .toInt(); // Cassia නම් Main Stock එකත් අප්ඩේට් වෙයි
    }

    await http.put(
      Uri.parse(url),
      headers: {"Content-Type": "application/json"},
      body: json.encode(body),
    );
  }
}
