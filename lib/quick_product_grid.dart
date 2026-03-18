import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';

class QuickProductGrid extends StatefulWidget {
  final Function(String, dynamic) onAddToCart;
  final int Function(dynamic) getLiveStock;
  final String baseUrl, ck, cs;
  final Color primaryGreen;

  const QuickProductGrid({
    super.key,
    required this.onAddToCart,
    required this.getLiveStock,
    required this.baseUrl,
    required this.ck,
    required this.cs,
    required this.primaryGreen,
  });

  @override
  State<QuickProductGrid> createState() => _QuickProductGridState();
}

class _QuickProductGridState extends State<QuickProductGrid> {
  List<Map<String, dynamic>?> quickProducts = List.filled(50, null);

  @override
  void initState() {
    super.initState();
    _loadQuickProducts();
  }

  Future<void> _loadQuickProducts() async {
    var doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('quick_grid')
        .get();
    if (doc.exists && mounted) {
      List d = (doc.data() as Map<String, dynamic>)['items'] ?? [];
      setState(() {
        for (int i = 0; i < d.length; i++) {
          if (i < 50) {
            quickProducts[i] = d[i] != null
                ? Map<String, dynamic>.from(d[i] as Map)
                : null;
          }
        }
      });
    }
  }

  Future<void> _saveQuickProducts() async {
    await FirebaseFirestore.instance
        .collection('settings')
        .doc('quick_grid')
        .set({'items': quickProducts});
  }

  void _showProductPicker(int gridIndex) {
    List res = [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setMState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "Search Store...",
                  prefixIcon: Icon(Icons.search, color: widget.primaryGreen),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) async {
                  if (v.length < 3) return;
                  final r = await http.get(
                    Uri.parse(
                      "${widget.baseUrl}/products?consumer_key=${widget.ck}&consumer_secret=${widget.cs}&search=$v&per_page=30",
                    ),
                  );
                  if (r.statusCode == 200) {
                    setMState(() => res = json.decode(r.body));
                  }
                },
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: res.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(res[i]['name']),
                    onTap: () => _showCustomizeDialog(gridIndex, res[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomizeDialog(int gridIndex, dynamic p) {
    final nameC = TextEditingController(text: p['name']);
    String img = (p['images'] as List).isNotEmpty ? p['images'][0]['src'] : "";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Customize Display"),
        content: TextField(
          controller: nameC,
          decoration: const InputDecoration(labelText: "Display Name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                quickProducts[gridIndex] = {
                  'id': p['id'],
                  'name': nameC.text,
                  'image': img,
                  'price': double.tryParse(p['price'].toString()) ?? 0.0,
                  'sku': p['sku'],
                };
              });
              _saveQuickProducts();
              Navigator.pop(context); // Close Customize
              Navigator.pop(context); // Close Picker
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 21, // දැනට 21ක් පෙන්නමු
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.1,
        mainAxisSpacing: 6,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        var p = quickProducts[index];
        return GestureDetector(
          onTap: () => p == null
              ? _showProductPicker(index)
              : widget.onAddToCart(p['name'], p),
          onLongPress: () {
            setState(() => quickProducts[index] = null);
            _saveQuickProducts();
          },
          child: Container(
            decoration: BoxDecoration(
              color: p == null ? Colors.grey[50] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: p == null
                    ? Colors.grey[200]!
                    : widget.primaryGreen.withValues(alpha: 0.2),
              ),
            ),
            child: p == null
                ? Icon(Icons.add, color: Colors.grey[400])
                : Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: (p['image'] != "" && p['image'] != null)
                              ? CachedNetworkImage(
                                  imageUrl: p['image'],
                                  fit: BoxFit.cover,
                                )
                              : const Icon(
                                  Icons.restaurant,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        child: Text(
                          p['name'] ?? "",
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        decoration: BoxDecoration(
                          color: widget.primaryGreen,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(11),
                          ),
                        ),
                        child: Text(
                          "Stock: ${widget.getLiveStock(p)}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 7,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
