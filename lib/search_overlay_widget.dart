import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SearchOverlayWidget extends StatelessWidget {
  final List searchResults;
  final Color primaryGreen;
  final Color accentGreen;
  final Function(String, dynamic) onProductSelect;
  final int Function(dynamic) getLiveStock;

  const SearchOverlayWidget({
    super.key,
    required this.searchResults,
    required this.primaryGreen,
    required this.accentGreen,
    required this.onProductSelect,
    required this.getLiveStock,
  });

  @override
  Widget build(BuildContext context) {
    if (searchResults.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      right: 0,
      width: MediaQuery.of(context).size.width * 0.6,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: ListView.builder(
          itemCount: searchResults.length,
          itemBuilder: (context, i) {
            var p = searchResults[i];
            String imgUrl =
                (p['images'] != null && (p['images'] as List).isNotEmpty)
                ? p['images'][0]['src']
                : "";

            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: imgUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imgUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[200]),
                        errorWidget: (context, url, error) =>
                            Icon(Icons.shopping_bag, color: primaryGreen),
                      )
                    : Icon(Icons.shopping_bag, color: primaryGreen),
              ),
              title: Text(
                p['name'] ?? "Unknown Product",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                "Price: €${p['price']} | Stock: ${getLiveStock(p)}",
                style: TextStyle(color: accentGreen),
              ),
              onTap: () => onProductSelect(p['name'], p),
            );
          },
        ),
      ),
    );
  }
}
