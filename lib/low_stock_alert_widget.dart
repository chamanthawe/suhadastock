import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class LowStockAlertWidget extends StatelessWidget {
  final Map<String, dynamic> product;
  final int currentStock;
  final VoidCallback onClose;

  const LowStockAlertWidget({
    super.key,
    required this.product,
    required this.currentStock,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Screen එකේ මැදට පෙන්වීමට Center භාවිතා කර ඇත
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width:
              MediaQuery.of(context).size.width *
              0.4, // Screen එකෙන් 40% ක පළලක්
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 320),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(color: Colors.orangeAccent, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header කොටස
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 35,
                      ),
                      SizedBox(width: 10),
                      Text(
                        "LOW STOCK ALERT",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 18,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.cancel,
                      color: Colors.grey,
                      size: 28,
                    ),
                    onPressed: onClose,
                  ),
                ],
              ),
              const Divider(thickness: 1.5),
              const SizedBox(height: 15),

              // Product Image එක මැදට ලොකුවට
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: CachedNetworkImage(
                  imageUrl: product['image'] ?? "",
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    width: 150,
                    height: 150,
                    color: Colors.grey[100],
                    child: const Icon(
                      Icons.image_not_supported,
                      size: 50,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Product Name
              Text(
                product['name'] ?? "Unknown Product",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),

              // Stock Status
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  "Only $currentStock Items Left!",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Reorder Message
              const Text(
                "Please reorder this product to avoid \nrunning out of stock.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
