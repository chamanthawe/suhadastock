import 'package:flutter/material.dart';

class CalculatorSection extends StatelessWidget {
  final int rawInput;
  final bool isPriceMode;
  final Color primaryGreen;
  final Color lightGreenBg;
  final Function(String) onKeyTap;
  final VoidCallback onConfirmToggle;

  const CalculatorSection({
    super.key,
    required this.rawInput,
    required this.isPriceMode,
    required this.primaryGreen,
    required this.lightGreenBg,
    required this.onKeyTap,
    required this.onConfirmToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.lightGreen,
        border: Border(left: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        children: [
          // Display Area
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPriceMode ? Colors.orange[50] : lightGreenBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isPriceMode
                    ? Colors.orange[200]!
                    : primaryGreen.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              isPriceMode
                  ? "€ ${(rawInput / 100.0).toStringAsFixed(2)}"
                  : "${(rawInput / 1000.0).toStringAsFixed(3)} kg",
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isPriceMode ? Colors.orange[900] : primaryGreen,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Number Pad
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 3.7,
              children:
                  ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "00", "C"]
                      .map(
                        (key) => ElevatedButton(
                          onPressed: () => onKeyTap(key),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: key == "C"
                                ? Colors.red[50]
                                : lightGreenBg,
                            foregroundColor: key == "C"
                                ? Colors.red
                                : primaryGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            key,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 5),
          // Action Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 45),
              backgroundColor: isPriceMode ? Colors.orange[800] : primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onConfirmToggle,
            child: Text(
              isPriceMode ? "CONFIRM" : "PRICE MODE",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
