import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart'; // මේක හරියට තියෙන්න ඕනේ
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterManager {
  // LateInitializationError එක සම්පූර්ණයෙන්ම නැති කිරීමට dynamic ලෙස තබා මුලින්ම null කරමු
  static dynamic printer;
  static bool isConnected = false;

  static Future<void> saveIP(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_ip', ip.trim());
  }

  static Future<String?> getSavedIP() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_ip');
  }

  static Future<bool> connect(String ip) async {
    try {
      // කලින් තිබූ printer instance එක සම්පූර්ණයෙන්ම ඉවත් කරමු
      if (printer != null) {
        try {
          await printer.disconnect();
        } catch (_) {}
        printer = null;
      }

      final profile = await CapabilityProfile.load();
      // මෙහිදී NetworkPrinter ව්‍යුහය අලුතින්ම සාදා ගමු
      printer = NetworkPrinter(PaperSize.mm80, profile);

      // Timeout එක තත්පර 3කට වඩා වැඩි කිරීමෙන් socket එකට සූදානම් වීමට කාලය ලැබේ
      await printer.connect(
        ip.trim(),
        port: 9100,
        timeout: const Duration(seconds: 5),
      );

      isConnected = true;
      await saveIP(ip);
      return true;
    } catch (e) {
      debugPrint("Connect error: $e");
      isConnected = false;
      printer = null;
      return false;
    }
  }

  // පින්ට් කරන තැනදී 'LateInitializationError' එක එන එක නවත්වන්න මේ function එක පාවිච්චි කරන්න
  static bool isReadyToPrint() {
    if (printer == null || !isConnected) return false;

    // මෙතැනදී අපි socket එක initialize වෙලාද කියා සරලව පරීක්ෂා කරනවා
    try {
      // printer instance එක ඇතුළේ socket එක check කිරීමට උත්සාහ කරයි
      return printer != null;
    } catch (e) {
      return false;
    }
  }
}
