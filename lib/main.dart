import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'firebase_options.dart';
import 'product_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }
  runApp(const SuhadaInventoryApp());
}

class SuhadaInventoryApp extends StatelessWidget {
  const SuhadaInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Suhada Inventory',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
      ),
      home: const InitialDataLoader(), // මුලින්ම දත්ත Load කරන Screen එක
    );
  }
}

class InitialDataLoader extends StatefulWidget {
  const InitialDataLoader({super.key});

  @override
  State<InitialDataLoader> createState() => _InitialDataLoaderState();
}

class _InitialDataLoaderState extends State<InitialDataLoader> {
  bool _isLoading = true; // Warning එක නැති වීමට මෙය දැන් UI එකේ පාවිච්චි වේ
  List allProducts = [];

  // ඔබේ WooCommerce විස්තර මෙහි ඇතුළත් කරන්න
  final String baseUrl = "https://yourstore.com";
  final String ck = "ck_xxxxxxxxxxxxxxxxxxxxxxxx";
  final String cs = "cs_xxxxxxxxxxxxxxxxxxxxxxxx";

  @override
  void initState() {
    super.initState();
    fetchAllProducts();
  }

  Future<void> fetchAllProducts() async {
    List temporaryList = [];
    try {
      // පිටු 10ක් (බඩු 1000ක්) දක්වා ලෝඩ් කිරීමේ හැකියාව
      for (int i = 1; i <= 10; i++) {
        final response = await http.get(
          Uri.parse(
            "$baseUrl/wp-json/wc/v3/products?consumer_key=$ck&consumer_secret=$cs&per_page=100&page=$i",
          ),
        );

        if (response.statusCode == 200) {
          List data = json.decode(response.body);
          if (data.isEmpty) break; // තවත් බඩු නැතිනම් නවත්වන්න
          temporaryList.addAll(data);

          // දත්ත ලැබෙන ප්‍රමාණය අනුව UI එක Update කරන්න
          setState(() {
            allProducts = temporaryList;
          });
        } else {
          break;
        }
      }
    } catch (e) {
      debugPrint("Data Fetch Error: $e");
    }

    if (mounted) {
      setState(() {
        _isLoading = false; // Loading අවසන් බව දැන්වීමට
      });

      // දත්ත සියල්ල ලැබුණු පසු ProductListScreen එකට මාරු වීම
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ProductListScreen(initialProducts: allProducts),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // _isLoading true නම් රෝදය කැරකෙනවා, නැතිනම් Redirect පණිවිඩය පෙන්වනවා
            if (_isLoading) ...[
              const CircularProgressIndicator(color: Colors.teal),
              const SizedBox(height: 25),
              const Text(
                "Suhada Inventory Loading...",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                "Fetched Products: ${allProducts.length}",
                style: TextStyle(color: Colors.grey[600]),
              ),
            ] else ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 15),
              const Text("Ready to Go!"),
            ],
          ],
        ),
      ),
    );
  }
}
