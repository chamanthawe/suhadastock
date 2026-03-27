import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BranchFinanceScreen extends StatefulWidget {
  final String branchName;
  const BranchFinanceScreen({super.key, required this.branchName});

  @override
  State<BranchFinanceScreen> createState() => _BranchFinanceScreenState();
}

class _BranchFinanceScreenState extends State<BranchFinanceScreen> {
  final Color darkGreen = const Color(0xFF0D1B15);
  final Color accentGreen = const Color(0xFF00E676);
  DateTimeRange? selectedRange;

  // --- Card Machine මුදල ලබාගන්නා Dialog එක ---
  Future<void> _showCardAmountDialog(
    List<QueryDocumentSnapshot> docs,
    double totalSales,
    double profit,
    Map<String, int> topProducts,
    double totalBills,
    double shortEatsExpense, // 🔥 එකතු කල නව Parameter එක
    double shortEatsProfit, // 🔥 එකතු කල නව Parameter එක
  ) async {
    final TextEditingController cardController = TextEditingController(
      text: "0.00",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accentGreen.withOpacity(0.5)),
        ),
        title: const Text(
          "Card Machine Total",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter today's total card payments received:",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: cardController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixText: "€ ",
                prefixStyle: TextStyle(color: accentGreen),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: accentGreen),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              double cardAmount = double.tryParse(cardController.text) ?? 0.0;
              Navigator.pop(context);
              _generatePdf(
                docs,
                totalSales,
                profit,
                topProducts,
                totalBills,
                cardAmount,
                shortEatsExpense, // 🔥
                shortEatsProfit, // 🔥
              );
            },
            child: const Text(
              "Generate PDF",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ඕඩර් එකක් Reprint කිරීමේ Logic එක ---
  Future<void> _reprintOrder(Map<String, dynamic> data, String orderId) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "REPRINT RECEIPT",
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
            pw.Text("Shop: ${widget.branchName}"),
            pw.Text("Date: ${data['date']} | Time: ${data['time']}"),
            pw.Text("Order ID: ${orderId.toUpperCase()}"),
            pw.SizedBox(height: 10),
            pw.Text(
              "Items:",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            ...(data['items'] as List).map(
              (item) => pw.Text(
                "- ${item['name']} x${item['qty']} : EUR ${item['price']}",
              ),
            ),
            pw.Divider(),
            pw.Text(
              "TOTAL: EUR ${data['total_sales'] ?? data['total']}",
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // --- මුළු Report එක PDF ලෙස ලබා ගැනීම (Card Machine සහ Short Eats සහිතව) ---
  Future<void> _generatePdf(
    List<QueryDocumentSnapshot> docs,
    double totalSales,
    double profit,
    Map<String, int> topProducts,
    double totalBills,
    double cardAmount,
    double shortEatsExpense, // 🔥
    double shortEatsProfit, // 🔥
  ) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    String reportDate = selectedRange == null
        ? DateFormat('yyyy-MM-dd').format(DateTime.now())
        : "${DateFormat('yyyy-MM-dd').format(selectedRange!.start)} to ${DateFormat('yyyy-MM-dd').format(selectedRange!.end)}";

    double staffTotal = 0.0;
    try {
      var staffSnapshot = await FirebaseFirestore.instance
          .collection('staff_orders')
          .where('shop', isEqualTo: widget.branchName)
          .get();
      var filteredStaff = staffSnapshot.docs.where((doc) {
        String dStr = doc['date'] ?? "";
        if (selectedRange == null)
          return dStr == DateFormat('yyyy-MM-dd').format(DateTime.now());
        DateTime d = DateFormat('yyyy-MM-dd').parse(dStr);
        return d.isAfter(
              selectedRange!.start.subtract(const Duration(days: 1)),
            ) &&
            d.isBefore(selectedRange!.end.add(const Duration(days: 1)));
      }).toList();
      for (var sDoc in filteredStaff) {
        staffTotal +=
            double.tryParse(sDoc['total_value']?.toString() ?? '0') ?? 0;
      }
    } catch (e) {
      debugPrint("Error: $e");
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Suhada S.R.L.S',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Branch: ${widget.branchName}',
                        style: pw.TextStyle(fontSize: 14),
                      ),
                      pw.Text(
                        'Period: $reportDate',
                        style: pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Generated: $dateStr',
                    style: pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            pw.TableHelper.fromTextArray(
              headers: ['Metric', 'Value (EUR)'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              data: [
                ['Total Sales', totalSales.toStringAsFixed(2)],
                ['Card Machine Total (-)', cardAmount.toStringAsFixed(2)],
                ['Bill Expenses (-)', totalBills.toStringAsFixed(2)],
                [
                  'Short Eats Supplier Payout (-)',
                  shortEatsExpense.toStringAsFixed(2),
                ], // 🔥
                [
                  'Final Physical Cash Balance',
                  (totalSales - totalBills - cardAmount - shortEatsExpense)
                      .toStringAsFixed(2), // 🔥
                ],
                [
                  'Net Profit (POS + ShortEats)',
                  (profit + shortEatsProfit).toStringAsFixed(2),
                ], // 🔥
                ['Staff Consumption', staffTotal.toStringAsFixed(2)],
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              "Note: Transaction list excluded. Card amount manually entered.",
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ];
        },
      ),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  double _calculateOrderProfit(Map<String, dynamic> orderData) {
    if (orderData['net_profit'] != null)
      return double.tryParse(orderData['net_profit'].toString()) ?? 0.0;
    double totalProfit = 0.0;
    List items = orderData['items'] ?? [];
    for (var item in items) {
      double price = double.tryParse(item['price'].toString()) ?? 0.0;
      double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
      totalProfit += (price * qty);
    }
    return totalProfit;
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
            primary: accentGreen,
            onPrimary: Colors.black,
            surface: darkGreen,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => selectedRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      backgroundColor: darkGreen,
      body: Stack(
        children: [
          _buildBackgroundDecor(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('shop', isEqualTo: widget.branchName)
                  .snapshots(),
              builder: (context, orderSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('bills')
                      .where('shop', isEqualTo: widget.branchName)
                      .snapshots(),
                  builder: (context, billSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection(
                            'short_eats_settlements',
                          ) // 🔥 නව Short eats collection එක
                          .where('shop', isEqualTo: widget.branchName)
                          .snapshots(),
                      builder: (context, shortEatSnapshot) {
                        if (!orderSnapshot.hasData ||
                            !billSnapshot.hasData ||
                            !shortEatSnapshot.hasData)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );

                        var filteredOrders = orderSnapshot.data!.docs.where((
                          doc,
                        ) {
                          String dStr = doc['date'] ?? "";
                          if (selectedRange == null) return dStr == today;
                          DateTime d = DateFormat('yyyy-MM-dd').parse(dStr);
                          return d.isAfter(
                                selectedRange!.start.subtract(
                                  const Duration(days: 1),
                                ),
                              ) &&
                              d.isBefore(
                                selectedRange!.end.add(const Duration(days: 1)),
                              );
                        }).toList();

                        var filteredBills = billSnapshot.data!.docs.where((
                          doc,
                        ) {
                          var data = doc.data() as Map<String, dynamic>;
                          String dStr = (data['date_time'] ?? "")
                              .split('|')[0]
                              .trim();
                          if (selectedRange == null) return dStr == today;
                          DateTime d = DateFormat('yyyy-MM-dd').parse(dStr);
                          return d.isAfter(
                                selectedRange!.start.subtract(
                                  const Duration(days: 1),
                                ),
                              ) &&
                              d.isBefore(
                                selectedRange!.end.add(const Duration(days: 1)),
                              );
                        }).toList();

                        // 🔥 Short Eats Settlements filtering logic
                        var filteredShortEats = shortEatSnapshot.data!.docs
                            .where((doc) {
                              String dStr = doc['date'] ?? "";
                              if (selectedRange == null) return dStr == today;
                              DateTime d = DateFormat('yyyy-MM-dd').parse(dStr);
                              return d.isAfter(
                                    selectedRange!.start.subtract(
                                      const Duration(days: 1),
                                    ),
                                  ) &&
                                  d.isBefore(
                                    selectedRange!.end.add(
                                      const Duration(days: 1),
                                    ),
                                  );
                            })
                            .toList();

                        filteredOrders.sort(
                          (a, b) =>
                              (b['time'] ?? "").compareTo(a['time'] ?? ""),
                        );

                        double grandTotalSales = 0.0;
                        double grandProfit = 0.0;
                        double totalBillExpenses = 0.0;
                        double shortEatsExpense = 0.0; // 🔥
                        double shortEatsProfit = 0.0; // 🔥
                        Map<String, double> salesByDate = {};
                        Map<String, int> topProducts = {};

                        for (var doc in filteredOrders) {
                          var data = doc.data() as Map<String, dynamic>;
                          double total =
                              double.tryParse(
                                data['total_sales']?.toString() ??
                                    data['total']?.toString() ??
                                    '0',
                              ) ??
                              0;
                          grandTotalSales += total;
                          grandProfit += _calculateOrderProfit(data);
                          salesByDate[data['date']] =
                              (salesByDate[data['date']] ?? 0) + total;
                          List items = data['items'] ?? [];
                          for (var i in items) {
                            topProducts[i['name']] =
                                (topProducts[i['name']] ?? 0) +
                                (int.tryParse(i['qty'].toString()) ?? 1);
                          }
                        }
                        for (var doc in filteredBills) {
                          var data = doc.data() as Map<String, dynamic>;
                          totalBillExpenses +=
                              double.tryParse(
                                data['amount']?.toString() ?? '0',
                              ) ??
                              0;
                        }

                        // 🔥 Short Eats ගණනය කිරීම
                        for (var doc in filteredShortEats) {
                          var data = doc.data() as Map<String, dynamic>;
                          List items = data['items'] ?? [];
                          for (var item in items) {
                            shortEatsExpense +=
                                double.tryParse(
                                  item['total_supplier_pay']?.toString() ?? '0',
                                ) ??
                                0;
                            shortEatsProfit +=
                                double.tryParse(
                                  item['total_profit']?.toString() ?? '0',
                                ) ??
                                0;
                          }
                        }

                        // Final Physical Cash Calculation
                        double physicalCash =
                            grandTotalSales -
                            totalBillExpenses -
                            shortEatsExpense;

                        return CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            _buildAppBar(
                              filteredOrders,
                              grandTotalSales,
                              grandProfit +
                                  shortEatsProfit, // 🔥 ලාභයට ShortEats එකතු කරයි
                              topProducts,
                              totalBillExpenses,
                              shortEatsExpense, // 🔥
                              shortEatsProfit, // 🔥
                            ),
                            SliverToBoxAdapter(
                              child: Column(
                                children: [
                                  _build3DSummary(
                                    grandTotalSales,
                                    grandProfit + shortEatsProfit,
                                    physicalCash,
                                  ), // 🔥
                                  _buildShortEatsSummaryCard(
                                    shortEatsExpense,
                                    shortEatsProfit,
                                  ), // 🔥 New Section
                                  _buildBillSummaryCard(
                                    totalBillExpenses,
                                    filteredBills,
                                  ),
                                ],
                              ),
                            ),
                            if (selectedRange != null) ...[
                              SliverToBoxAdapter(
                                child: _buildSectionLabel(
                                  "Sales Growth (3D Perspective)",
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: _buildCustom3DChart(salesByDate),
                              ),
                              SliverToBoxAdapter(
                                child: _buildSectionLabel(
                                  "Top 5 Selling Products",
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: _buildTop5List(topProducts),
                              ),
                            ] else ...[
                              SliverToBoxAdapter(
                                child: _buildSectionLabel(
                                  "Today's Live Orders",
                                ),
                              ),
                              _buildTodayOrdersList(filteredOrders),
                            ],
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 100),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentGreen,
        onPressed: () => _selectDateRange(context),
        icon: Icon(
          selectedRange == null ? Icons.date_range : Icons.restart_alt,
          color: Colors.black,
        ),
        label: Text(
          selectedRange == null ? "Select Range" : "Reset To Today",
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // 🔥 Short Eats සාරාංශ පුවරුව
  Widget _buildShortEatsSummaryCard(double expense, double profit) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: accentGreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "SHORT EATS CONSIGNMENTS",
                style: TextStyle(
                  color: accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Net Profit: €${profit.toStringAsFixed(2)}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Supplier Payout (Out):",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                "€${expense.toStringAsFixed(2)}",
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBillSummaryCard(
    double total,
    List<QueryDocumentSnapshot> bills,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "BILL EXPENSES",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Total: €${total.toStringAsFixed(2)}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (bills.isEmpty)
            const Text(
              "No bills paid today.",
              style: TextStyle(color: Colors.white24, fontSize: 12),
            )
          else
            ...bills.map((b) {
              var data = b.data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "- ${data['bill_name'] ?? 'Bill'}",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      "€${data['amount']}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBackgroundDecor() => Positioned.fill(
    child: Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.5,
          colors: [accentGreen.withOpacity(0.03), Colors.transparent],
        ),
      ),
    ),
  );

  Widget _buildAppBar(
    List<QueryDocumentSnapshot> docs,
    double total,
    double profit,
    Map<String, int> top,
    double bills,
    double shortEatsExpense, // 🔥
    double shortEatsProfit, // 🔥
  ) => SliverAppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    leading: const BackButton(color: Colors.white),
    title: Text(
      "${widget.branchName} INSIGHTS",
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    ),
    centerTitle: true,
    actions: [
      IconButton(
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        onPressed: () => _showCardAmountDialog(
          docs,
          total,
          profit,
          top,
          bills,
          shortEatsExpense,
          shortEatsProfit,
        ), // 🔥
      ),
      const SizedBox(width: 10),
    ],
  );

  Widget _build3DSummary(double total, double profit, double physicalCash) =>
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                _summaryCard(
                  "TOTAL SALES",
                  "€${total.toStringAsFixed(2)}",
                  Colors.blueAccent,
                ),
                const SizedBox(width: 15),
                _summaryCard(
                  "NET PROFIT",
                  "€${profit.toStringAsFixed(2)}",
                  accentGreen,
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                _summaryCard(
                  "PHYSICAL CASH BALANCE",
                  "€${physicalCash.toStringAsFixed(2)}",
                  Colors.orangeAccent,
                ),
              ],
            ),
          ],
        ),
      );

  Widget _summaryCard(String title, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildCustom3DChart(Map<String, double> salesData) {
    var sortedEntries = salesData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (sortedEntries.isEmpty) return const SizedBox();
    double maxValue = salesData.values.reduce((a, b) => a > b ? a : b);
    if (maxValue == 0) maxValue = 1;
    return Container(
      height: 250,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(30),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: sortedEntries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      "€${e.value.toStringAsFixed(1)}",
                      style: TextStyle(
                        color: accentGreen.withOpacity(0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CustomPaint(
                      size: Size(30, 140 * (e.value / maxValue)),
                      painter: Prism3DPainter(accentGreen),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      e.key.substring(5),
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTop5List(Map<String, int> products) {
    var top5 =
        (products.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: top5
            .map(
              (e) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Text(
                      (top5.indexOf(e) + 1).toString(),
                      style: TextStyle(
                        color: accentGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      "${e.value} Qty",
                      style: TextStyle(
                        color: accentGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTodayOrdersList(List<QueryDocumentSnapshot> docs) => SliverList(
    delegate: SliverChildBuilderDelegate((context, index) {
      var data = docs[index].data() as Map<String, dynamic>;
      double saleAmount =
          double.tryParse(
            data['total_sales']?.toString() ?? data['total']?.toString() ?? '0',
          ) ??
          0;
      double orderProfit = _calculateOrderProfit(data);
      return GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: darkGreen,
              title: const Text(
                "Order Action",
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                "Do you want to reprint this order?",
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: accentGreen),
                  onPressed: () {
                    Navigator.pop(context);
                    _reprintOrder(data, docs[index].id);
                  },
                  child: const Text(
                    "Reprint",
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            title: Text(
              data['time'] ?? "--:--",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              "ID: ${docs[index].id.substring(0, 5).toUpperCase()}",
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "Total: €${saleAmount.toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Profit: €${orderProfit.toStringAsFixed(2)}",
                  style: TextStyle(
                    color: accentGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }, childCount: docs.length),
  );

  Widget _buildSectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(25, 25, 25, 10),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white30,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class Prism3DPainter extends CustomPainter {
  final Color baseColor;
  Prism3DPainter(this.baseColor);
  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    double depth = 10.0;
    final mainPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [baseColor, baseColor.withOpacity(0.5)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final sidePaint = Paint()..color = baseColor.withOpacity(0.3);
    final topPaint = Paint()..color = baseColor.withOpacity(0.9);
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        0,
        0,
        size.width - depth,
        size.height,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      mainPaint,
    );
    Path sidePath = Path()
      ..moveTo(size.width - depth, 0)
      ..lineTo(size.width, -depth)
      ..lineTo(size.width, size.height - depth)
      ..lineTo(size.width - depth, size.height)
      ..close();
    canvas.drawPath(sidePath, sidePaint);
    Path topPath = Path()
      ..moveTo(0, 0)
      ..lineTo(depth, -depth)
      ..lineTo(size.width, -depth)
      ..lineTo(size.width - depth, 0)
      ..close();
    canvas.drawPath(topPath, topPaint);
    canvas.drawShadow(topPath, baseColor, 3, false);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
