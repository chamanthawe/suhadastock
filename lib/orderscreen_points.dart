import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class OrderScreenPoints extends StatelessWidget {
  final Map<String, dynamic> customerData;
  final double currentTotal;
  final Function(double discount, int pointsUsed) onApplyPoints;

  const OrderScreenPoints({
    super.key,
    required this.customerData,
    required this.currentTotal,
    required this.onApplyPoints,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('loyalty_config')
          .snapshots(),
      builder: (context, configSnapshot) {
        if (!configSnapshot.hasData || !configSnapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        var config = configSnapshot.data!.data() as Map<String, dynamic>;
        int pointsToEuro = config['points_to_euro_value'] ?? 100;
        int customerPoints = customerData['points'] ?? 0;

        // යුරෝ 1ක් අඩු කිරීමට තරම් points තිබේදැයි බැලීම
        if (customerPoints < pointsToEuro) return const SizedBox.shrink();

        double maxEuroDiscount = (customerPoints / pointsToEuro)
            .floorToDouble();
        // බිලට වඩා වැඩි වට්ටමක් දිය නොහැක
        if (maxEuroDiscount > currentTotal)
          maxEuroDiscount = currentTotal.floorToDouble();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade700,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: InkWell(
            onTap: () => _showRedeemDialog(
              context,
              customerPoints,
              pointsToEuro,
              maxEuroDiscount,
            ),
            child: Row(
              children: [
                const Icon(Icons.stars, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "LOYALTY POINTS AVAILABLE!",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        "You can save up to €${maxEuroDiscount.toInt()}. Click to redeem.",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.touch_app, color: Colors.white70, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRedeemDialog(
    BuildContext context,
    int totalPoints,
    int rate,
    double maxDiscount,
  ) {
    final controller = TextEditingController(text: "1");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Redeem Points"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Total Points: $totalPoints"),
            Text(
              "Rate: $rate Pts = €1.00",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            const Text("How many Euros (€) to discount?"),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(prefixText: "€ "),
            ),
            Text(
              "Max allowed: €${maxDiscount.toInt()}",
              style: const TextStyle(color: Colors.red, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
            ),
            onPressed: () {
              double inputEuro = double.tryParse(controller.text) ?? 0;
              if (inputEuro > 0 && inputEuro <= maxDiscount) {
                int pointsToDeduct = (inputEuro * rate).toInt();
                onApplyPoints(inputEuro, pointsToDeduct);
                Navigator.pop(ctx);
              }
            },
            child: const Text(
              "APPLY DISCOUNT",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
