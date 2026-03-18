import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'printer_manager.dart';

class ReceiptService {
  static Future<void> printOrder({
    required List<Map<String, dynamic>> cart,
    required double total,
    required double discount,
    required String selectedShop,
    bool isCredit = false,
    double cashReceived = 0, // අලුතින් එක් කළා
    double balance = 0, // අලුතින් එක් කළා
  }) async {
    if (PrinterManager.printer == null || !PrinterManager.isConnected) {
      throw Exception("Printer not connected. Please connect from settings.");
    }

    final p = PrinterManager.printer!;

    String shopAddress = "";
    String shopPhones = "";
    const String pIva = "15563521002";

    if (selectedShop.toLowerCase().contains("cassia")) {
      shopAddress = "Via Cassia 530 A/B Roma";
      shopPhones = "320 1730 853 / 068 9511 895";
    } else if (selectedShop.toLowerCase().contains("battistini")) {
      shopAddress = "Via Mattia Battistini 103 Roma";
      shopPhones = "347 510 8271 / 068 9511 895";
    }

    try {
      // 1. Header Info
      p.text(
        'SUHADA S.R.L.S.',
        styles: const PosStyles(
          bold: true,
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      p.text(shopAddress, styles: const PosStyles(align: PosAlign.center));
      p.text(
        "Tel: $shopPhones",
        styles: const PosStyles(align: PosAlign.center),
      );
      p.text(
        "P.IVA: $pIva",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );

      p.feed(1);

      p.text(
        isCredit ? 'CREDIT RECEIPT' : 'OFFICIAL RECEIPT',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          reverse: isCredit,
        ),
      );

      p.text(
        'Date: ${DateTime.now().toString().substring(0, 16)}',
        styles: const PosStyles(align: PosAlign.center),
      );
      p.hr();

      // --- Items Loop ---
      double totalSavingOnItems = 0;

      for (var item in cart) {
        String cleanName = _removeNonAscii(item['name']);
        if (cleanName.trim().isEmpty) cleanName = "Product Item";

        double qty = item['qty'] as double;
        String qtyDisplay = item['isWeighted'] == true
            ? qty.toStringAsFixed(3)
            : qty.toInt().toString();

        double currentPrice = item['price'] as double;
        double lineTotal = (item['finalPrice'] as double);

        p.text("$cleanName", styles: const PosStyles(bold: true));

        // භාණ්ඩයට Discount එකක් තිබේ නම් (ඔයා එවපු රූපයේ තිබූ ආකාරයට)
        bool hasItemDiscount =
            item.containsKey('discount') && item['discount'] > 0;

        if (hasItemDiscount) {
          double originalUnitPrice =
              currentPrice + (item['discount'] as double);
          totalSavingOnItems += (item['discount'] as double) * qty;

          p.text(
            " $qtyDisplay x EUR ${currentPrice.toStringAsFixed(2)}",
            styles: const PosStyles(align: PosAlign.left),
          );
          // රතු පාටින් රූපයේ සලකුණු කර තිබූ කොටස
          p.text(
            "  (Was: EUR ${originalUnitPrice.toStringAsFixed(2)})",
            styles: const PosStyles(align: PosAlign.left),
          );
          p.text(
            "  Discounted Price applied!",
            styles: const PosStyles(align: PosAlign.left),
          );

          p.text(
            lineTotal.toStringAsFixed(2),
            styles: const PosStyles(align: PosAlign.right),
          );
        } else {
          // සාමාන්‍ය භාණ්ඩයක් නම්
          p.row([
            PosColumn(
              text: " $qtyDisplay x EUR ${currentPrice.toStringAsFixed(2)}",
              width: 8,
            ),
            PosColumn(
              text: lineTotal.toStringAsFixed(2),
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }
      p.hr();

      // --- Totals Section ---

      if (totalSavingOnItems > 0) {
        p.text(
          'Total Item Savings: EUR ${totalSavingOnItems.toStringAsFixed(2)}',
          styles: const PosStyles(align: PosAlign.right, bold: true),
        );
      }

      if (discount > 0) {
        p.text(
          'Extra Discount: -EUR ${discount.toStringAsFixed(2)}',
          styles: const PosStyles(align: PosAlign.right),
        );
      }

      p.text(
        'TOTAL TO PAY: EUR ${total.toStringAsFixed(2)}',
        styles: const PosStyles(
          bold: true,
          align: PosAlign.right,
          height: PosTextSize.size1,
          width: PosTextSize.size1,
        ),
      );

      // --- Cash & Balance Section (නව අංගය) ---
      if (!isCredit && cashReceived > 0) {
        p.feed(1);
        p.row([
          PosColumn(
            text: 'CASH RECEIVED:',
            width: 8,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: 'EUR ${cashReceived.toStringAsFixed(2)}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
        p.row([
          PosColumn(
            text: 'BALANCE:',
            width: 8,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: 'EUR ${balance.toStringAsFixed(2)}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
      }

      p.feed(1);

      if (isCredit) {
        p.text(
          '--- CREDIT BASIS ---',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        p.feed(1);
      }

      p.text(
        'THANK YOU FOR CHOOSING SUHADA',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );

      p.text(
        'COME AGAIN...',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );

      p.feed(5);
      p.cut();
    } catch (e) {
      PrinterManager.isConnected = false;
      throw Exception("Print Error: $e");
    }
  }

  static String _removeNonAscii(String text) {
    return text.replaceAll(RegExp(r'[^\x00-\x7F]+'), '');
  }
}
