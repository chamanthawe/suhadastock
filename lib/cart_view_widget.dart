import 'package:flutter/material.dart';

class CartViewWidget extends StatelessWidget {
  final List<Map<String, dynamic>> globalCart;
  final List<Map<String, dynamic>> heldCart;
  final double globalDiscount;
  final double totalValue;
  final double totalProfit;
  final bool showSecretProfit;
  final Color primaryGreen;
  final Color lightGreenBg;
  final ScrollController scrollController;
  final VoidCallback onHoldCart;
  final VoidCallback onRecallCart;
  final Function(String, dynamic) onAddToCart;
  final Function(int) onRemoveItem;
  final VoidCallback onLongPressTotal;
  final VoidCallback onConfirmPrint;

  const CartViewWidget({
    super.key,
    required this.globalCart,
    required this.heldCart,
    required this.globalDiscount,
    required this.totalValue,
    required this.totalProfit,
    required this.showSecretProfit,
    required this.primaryGreen,
    required this.lightGreenBg,
    required this.scrollController,
    required this.onHoldCart,
    required this.onRecallCart,
    required this.onAddToCart,
    required this.onRemoveItem,
    required this.onLongPressTotal,
    required this.onConfirmPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: lightGreenBg.withValues(alpha: 0.3),
      child: Column(
        children: [
          // Hold & Recall Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: globalCart.isEmpty ? null : onHoldCart,
                    icon: const Icon(Icons.pause_circle_outline, size: 18),
                    label: const Text("HOLD", style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[800],
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Badge(
                    label: Text(heldCart.length.toString()),
                    isLabelVisible: heldCart.isNotEmpty,
                    child: ElevatedButton.icon(
                      onPressed: heldCart.isEmpty ? null : onRecallCart,
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text(
                        "RECALL",
                        style: TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Cart Items List
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: globalCart.length,
              itemBuilder: (context, index) {
                final item = globalCart[index];
                final bool hasDiscount =
                    item['original_price'] != null &&
                    item['original_price'] > 0;
                return Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(color: primaryGreen, width: 4),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () => onAddToCart(item['name'], item),
                    onLongPress: () => onRemoveItem(index),
                    title: Text(
                      item['name'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['isWeighted'] == true
                              ? "${(item['qty'] as double).toStringAsFixed(3)} kg"
                              : "Qty: ${(item['qty'] as double).toInt()}",
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black,
                          ),
                        ),
                        if (hasDiscount)
                          Row(
                            children: [
                              Text(
                                "€${item['original_price'].toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                "€${item['price'].toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        else if (!item['id'].toString().contains('manual'))
                          Text(
                            "€${item['price'].toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                    trailing: Text(
                      "€${(item['finalPrice'] as double).toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Summary Section
          _buildSummarySection(),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (showSecretProfit)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Net Profit:",
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "€ ${totalProfit.toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onLongPress: onLongPressTotal,
                child: const Text(
                  "Total:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              Text(
                "€ ${totalValue.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: globalCart.isEmpty ? null : onConfirmPrint,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 45),
              backgroundColor: primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "Confirm & Print",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
