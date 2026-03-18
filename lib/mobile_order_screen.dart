import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Vibration සඳහා
import 'package:mobile_scanner/mobile_scanner.dart';

class MobileOrderScreen extends StatefulWidget {
  const MobileOrderScreen({super.key});

  @override
  State<MobileOrderScreen> createState() => _MobileOrderScreenState();
}

class _MobileOrderScreenState extends State<MobileOrderScreen> {
  final ScrollController _cartScrollController = ScrollController();
  List<Map<String, dynamic>> cartItems = [];
  String? orderId;
  String? displayOrderNum;
  bool isSaving = false;
  String? selectedShop;
  final TextEditingController _noteController = TextEditingController();

  final Color primaryGreen = const Color(0xFF1B5E20);
  final Color darkBg = const Color(0xFF0A2610);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showShopSelectionDialog(),
    );
  }

  void _scrollToBottom() {
    if (_cartScrollController.hasClients) {
      _cartScrollController.animateTo(
        _cartScrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showShopSelectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Select Shop",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1B5E20),
          ),
        ),
        content: const Text("ඔබ සිටින වෙළඳසැල තෝරන්න:"),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            onPressed: () {
              setState(() => selectedShop = 'cassia');
              Navigator.pop(context);
            },
            child: const Text("CASSIA", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[900],
            ),
            onPressed: () {
              setState(() => selectedShop = 'battistini');
              Navigator.pop(context);
            },
            child: const Text(
              "BATTISTINI",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  double get totalAmount {
    return cartItems.fold(0, (total, item) {
      double price = double.tryParse(item['price'].toString()) ?? 0.0;
      return total + (price * item['qty']);
    });
  }

  // --- Cart එකට එකතු කිරීම ---
  void _addToCart(Map<String, dynamic> data) {
    HapticFeedback.lightImpact(); // භාණ්ඩයක් එකතු වන විට කුඩා Vibration එකක්

    String stockField = selectedShop == 'cassia'
        ? 'cassia_stock'
        : 'battistini_stock';
    int availableStock = int.tryParse(data[stockField]?.toString() ?? '0') ?? 0;

    if (availableStock <= 0) {
      _showErrorSnackBar(
        "Out of Stock in $selectedShop! (Stock: $availableStock)",
      );
      return;
    }

    double sPrice =
        double.tryParse(data['shop_price']?.toString() ?? '0') ?? 0.0;
    double dPrice =
        double.tryParse(data['discount_price']?.toString() ?? '0') ?? 0.0;
    double finalPrice = (dPrice > 0) ? dPrice : sPrice;
    String currentSku = data['sku']?.toString() ?? '';

    int existingIndex = cartItems.indexWhere(
      (item) => item['sku'] == currentSku,
    );

    setState(() {
      if (existingIndex != -1) {
        _updateQuantity(existingIndex, 1, availableStock);
      } else {
        cartItems.add({
          'name': data['name'] ?? 'No Name',
          'price': finalPrice,
          'sku': currentSku,
          'qty': 1,
          'max_stock': availableStock,
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _updateQuantity(int index, int change, int maxStock) {
    setState(() {
      int newQty = cartItems[index]['qty'] + change;
      if (newQty > maxStock) {
        _showErrorSnackBar("උපරිම තොගය $maxStock කි!");
      } else if (newQty > 0) {
        cartItems[index]['qty'] = newQty;
      } else {
        cartItems.removeAt(index);
      }
    });
  }

  // --- සමාන Barcodes ඇති විට තෝරා ගැනීමට දෙන Dialog එක ---
  void _showProductSelectionDialog(List<QueryDocumentSnapshot> products) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white24),
        ),
        title: const Text(
          "Select Product",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: products.length,
            itemBuilder: (context, index) {
              var pData = products[index].data() as Map<String, dynamic>;
              return Card(
                color: Colors.white.withValues(alpha: 0.1),
                child: ListTile(
                  title: Text(
                    pData['name'] ?? 'No Name',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    "Price: €${pData['shop_price']} | SKU: ${pData['sku']}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _addToCart(pData);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _findProduct(String code) async {
    // සමාන barcodes සොයා ගැනීම (උදා: 1234 සහ 1234-1 යන දෙකම search කිරීමට query එකක්)
    // මෙහිදී sku field එක scan කළ code එකෙන් ආරම්භ වන සියල්ල සොයයි
    var snapshot = await FirebaseFirestore.instance
        .collection('products_data')
        .where('sku', isGreaterThanOrEqualTo: code)
        .where('sku', isLessThanOrEqualTo: '$code\uf8ff')
        .get();

    if (snapshot.docs.isEmpty) {
      _showErrorSnackBar("Product Not Found!");
    } else if (snapshot.docs.length == 1) {
      _addToCart(snapshot.docs.first.data());
    } else {
      // එකකට වඩා තිබේ නම් තෝරා ගැනීමට Dialog එක පෙන්වයි
      _showProductSelectionDialog(snapshot.docs);
    }
  }

  // --- ඉතිරි UI කොටස් ---

  Future<void> _savePendingOrder() async {
    if (cartItems.isEmpty) return;
    setState(() => isSaving = true);
    try {
      final counterRef = FirebaseFirestore.instance
          .collection('order_counters')
          .doc('pending_counter');
      String formattedNum = await FirebaseFirestore.instance.runTransaction((
        transaction,
      ) async {
        DocumentSnapshot snapshot = await transaction.get(counterRef);
        int currentNum = (snapshot.exists && snapshot.data() != null)
            ? (snapshot.data() as Map<String, dynamic>)['last_num'] + 1
            : 1;
        transaction.set(counterRef, {'last_num': currentNum});
        return currentNum.toString().padLeft(4, '0');
      });

      var docRef = await FirebaseFirestore.instance
          .collection('pending_orders')
          .add({
            'order_no': formattedNum,
            'shop': selectedShop,
            'items': cartItems,
            'total_amount': totalAmount,
            'note': _noteController.text,
            'created_at': FieldValue.serverTimestamp(),
            'status': 'pending',
          });

      setState(() {
        orderId = docRef.id;
        displayOrderNum = formattedNum;
        isSaving = false;
        cartItems = [];
        _noteController.clear();
      });
    } catch (e) {
      setState(() => isSaving = false);
      _showErrorSnackBar("Error: $e");
    }
  }

  void _viewOrderBarcode(String docId, String orderNo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Order No: $orderNo",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Scan this at the counter",
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 20),
            bw.BarcodeWidget(
              barcode: bw.Barcode.code128(),
              data: docId,
              width: 250,
              height: 100,
              drawText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOrder(String docId) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Delete Order?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("No"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      await FirebaseFirestore.instance
          .collection('pending_orders')
          .doc(docId)
          .delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        elevation: 10,
        title: Text("Self-Order: ${selectedShop?.toUpperCase() ?? ''}"),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _showShopSelectionDialog,
          ),
        ],
      ),
      body: orderId != null ? _buildOrderSuccessUI() : _buildMainUI(),
      floatingActionButton: orderId == null
          ? FloatingActionButton.extended(
              onPressed: _openScanner,
              backgroundColor: Colors.orange[900],
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              label: const Text(
                "SCAN NOW",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildMainUI() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: cartItems.isEmpty
                ? const Center(
                    child: Text(
                      "Cart is empty.\nStart scanning items!",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    controller: _cartScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: cartItems.length,
                    itemBuilder: (context, i) => _buildCartCard(i),
                  ),
          ),
        ),
        if (cartItems.isNotEmpty) _buildCheckoutPanel(),
        const Divider(color: Colors.white24, thickness: 1),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            "PENDING ORDERS (TAP TO VIEW)",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('pending_orders')
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var orders = snapshot.data!.docs;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: orders.length,
                itemBuilder: (context, i) {
                  var o = orders[i].data() as Map<String, dynamic>;
                  String dId = orders[i].id;
                  String oNo = o['order_no'] ?? 'N/A';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () => _viewOrderBarcode(dId, oNo),
                      onLongPress: () => _deleteOrder(dId),
                      leading: CircleAvatar(
                        backgroundColor: primaryGreen,
                        child: Text(
                          oNo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      title: Text(
                        "Order No: $oNo",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "Total: €${(o['total_amount'] ?? 0).toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(
                        Icons.qr_code,
                        color: Colors.greenAccent,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCartCard(int i) {
    final item = cartItems[i];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: Colors.white.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          item['name'],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          "€${item['price']} | SKU: ${item['sku']}",
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: Container(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.redAccent,
                ),
                onPressed: () => _updateQuantity(i, -1, item['max_stock']),
              ),
              Text(
                "${item['qty']}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.greenAccent,
                ),
                onPressed: () => _updateQuantity(i, 1, item['max_stock']),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckoutPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: primaryGreen,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _noteController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Add a note...",
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.black12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TOTAL:",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "€${totalAmount.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontSize: 28,
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isSaving ? null : _savePendingOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "FINISH & GET BARCODE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    String searchText = "";
    showModalBottomSheet(
      context: context,
      backgroundColor: darkBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Search Product...",
                  hintStyle: TextStyle(color: Colors.white38),
                  prefixIcon: Icon(Icons.search, color: Colors.white),
                ),
                onChanged: (v) => setModalState(() => searchText = v),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('products_data')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var filtered = snapshot.data!.docs.where((d) {
                      var data = d.data() as Map<String, dynamic>;
                      String name = (data['name'] ?? "")
                          .toString()
                          .toLowerCase();
                      return name.contains(searchText.toLowerCase());
                    }).toList();
                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        var p = filtered[i].data() as Map<String, dynamic>;
                        return ListTile(
                          title: Text(
                            p['name'] ?? 'No Name',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            "Price: €${p['shop_price'] ?? '0.00'}",
                            style: const TextStyle(color: Colors.white60),
                          ),
                          onTap: () {
                            _addToCart(p);
                            Navigator.pop(context);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 350,
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              _findProduct(barcodes.first.rawValue ?? "");
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }

  Widget _buildOrderSuccessUI() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 100),
          const Text(
            "ORDER COMPLETED!",
            style: TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "ORDER NO: $displayOrderNum",
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: bw.BarcodeWidget(
              barcode: bw.Barcode.code128(),
              data: orderId!,
              width: 250,
              height: 100,
            ),
          ),
          const SizedBox(height: 50),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white24,
              minimumSize: const Size(200, 50),
            ),
            onPressed: () => setState(() {
              orderId = null;
              displayOrderNum = null;
            }),
            child: const Text(
              "BACK TO SCANNER",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
