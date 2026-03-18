import 'package:flutter/material.dart';

class ActionButtonsGrid extends StatelessWidget {
  final Color primaryGreen;
  final Color accentGreen;
  final Function(String) onQuickAction;
  final VoidCallback onDiscount;
  final VoidCallback onCredit;
  final VoidCallback onClear;
  final VoidCallback onStaff; // අලුතින් එකතු කළා

  const ActionButtonsGrid({
    super.key,
    required this.primaryGreen,
    required this.accentGreen,
    required this.onQuickAction,
    required this.onDiscount,
    required this.onCredit,
    required this.onClear,
    required this.onStaff, // අලුතින් එකතු කළා
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: GridView.count(
        crossAxisCount: 2, // UI එකට හානි නොවන පරිදි පේළි 2ම තබා ගත්තා
        childAspectRatio: 2.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          _actionCard(
            "Short Eats",
            primaryGreen,
            Icons.category_outlined,
            () => onQuickAction("Short Eats"),
          ),
          _actionCard(
            "Fish",
            primaryGreen,
            Icons.set_meal_outlined,
            () => onQuickAction("Fish"),
          ),
          _actionCard(
            "Quick List",
            accentGreen,
            Icons.flash_on_outlined,
            () => onQuickAction("Quick Product"),
          ),
          _actionCard(
            "Discount",
            Colors.teal[700]!,
            Icons.sell_outlined,
            onDiscount,
          ),
          _actionCard(
            "Credit",
            Colors.orange[800]!,
            Icons.history_edu,
            onCredit,
          ),

          // --- STAFF BUTTON ---
          _actionCard(
            "Staff",
            Colors.blueGrey[700]!,
            Icons.badge_outlined,
            onStaff,
          ),

          _actionCard("Clear", Colors.red[700]!, Icons.delete_outline, onClear),
        ],
      ),
    );
  }

  Widget _actionCard(
    String title,
    Color bg,
    IconData icon,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );
}
