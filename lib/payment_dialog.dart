import 'package:flutter/material.dart';

class PaymentDialog extends StatefulWidget {
  final double totalValue;
  final Color primaryGreen;
  final Color accentGreen;

  const PaymentDialog({
    super.key,
    required this.totalValue,
    required this.primaryGreen,
    required this.accentGreen,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  String calcInput = "";

  void _addValue(double value) {
    setState(() {
      double current = double.tryParse(calcInput) ?? 0;
      calcInput = (current + value).toStringAsFixed(2);
      if (calcInput.endsWith(".00")) {
        calcInput = calcInput.substring(0, calcInput.length - 3);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double currentInput = double.tryParse(calcInput) ?? 0;
    double currentBalance = (currentInput - widget.totalValue).clamp(
      0,
      double.infinity,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.70,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          _buildDisplayPanel(currentInput, currentBalance),
                          const SizedBox(height: 15),
                          _buildKeypad(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            " QUICK CASH",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildCurrencyGrid(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(currentInput, currentBalance),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      decoration: BoxDecoration(
        color: widget.primaryGreen,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "PAYMENT SETTLEMENT",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "Total: € ${widget.totalValue.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayPanel(double input, double balance) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: widget.primaryGreen.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5),
        ],
      ),
      child: Column(
        children: [
          _displayRow(
            "Cash",
            "€ ${calcInput.isEmpty ? "0.00" : calcInput}",
            widget.primaryGreen,
            20,
          ),
          const Divider(height: 30),
          _displayRow(
            "Change",
            "€ ${balance.toStringAsFixed(2)}",
            Colors.redAccent,
            20,
          ),
        ],
      ),
    );
  }

  Widget _displayRow(String label, String value, Color color, double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        Row(children: [_keyBtn("1"), _keyBtn("2"), _keyBtn("3")]),
        const SizedBox(height: 8),
        Row(children: [_keyBtn("4"), _keyBtn("5"), _keyBtn("6")]),
        const SizedBox(height: 8),
        Row(children: [_keyBtn("7"), _keyBtn("8"), _keyBtn("9")]),
        const SizedBox(height: 8),
        Row(
          children: [_keyBtn("."), _keyBtn("0"), _keyBtn("C", isClear: true)],
        ),
      ],
    );
  }

  Widget _keyBtn(String label, {bool isClear = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: () {
            setState(() {
              if (isClear) {
                calcInput = "";
              } else if (label == "." && !calcInput.contains(".")) {
                calcInput += label; // මෙතනට { } දැම්මා
              } else if (label != ".") {
                calcInput += label; // මෙතනටත් { } දැම්මා
              }
            });
          },
          child: Container(
            height: 53,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isClear ? Colors.red[50] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isClear ? Colors.red[100]! : Colors.grey[200]!,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 1,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: isClear ? Colors.red : widget.primaryGreen,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyGrid() {
    final List<Map<String, dynamic>> currencies = [
      {'val': 1.0, 'img': 'assets/images/eur1.jpg'},
      {'val': 2.0, 'img': 'assets/images/eur2.jpg'},
      {'val': 5.0, 'img': 'assets/images/eur5.jpg'},
      {'val': 10.0, 'img': 'assets/images/eur10.jpg'},
      {'val': 20.0, 'img': 'assets/images/eur20.jpg'},
      {'val': 50.0, 'img': 'assets/images/eur50.jpg'},
      {'val': 100.0, 'img': 'assets/images/eur100.jpg'},
      {'val': 200.0, 'img': 'assets/images/eur200.jpg'},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: currencies.length,
      itemBuilder: (context, index) {
        return InkWell(
          onTap: () => _addValue(currencies[index]['val']),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                currencies[index]['img'],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(
                    "€${currencies[index]['val'].toInt()}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(double input, double balance) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "CANCEL",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            flex: 2,
            child: GestureDetector(
              // තප්පර 3ක් පමණ තද කරගෙන සිටින විට ක්‍රියාත්මක වේ
              onLongPress: () {
                Navigator.pop(context, {
                  'cash': input,
                  'balance': balance,
                  'confirmOnly': true, // Firestore පමණක් update කිරීමට
                });
              },
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.pop(context, {
                    'cash': input,
                    'balance': balance,
                    'confirmOnly': false, // Print + Update කිරීමට
                  });
                },
                child: const Text(
                  "CONFIRM & PRINT",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
