import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stocksuhada/notification_panel.dart';

import 'add_product_screen.dart';
import 'bill_management_screen.dart';
import 'branch_finance_screen.dart';
import 'constants.dart';
import 'customer_list_screen.dart';
import 'mobile_order_screen.dart';
import 'order_request_screen.dart';
import 'order_screen.dart';
import 'printer_manager.dart';
import 'product_details_screen.dart';
import 'stock_update_screen.dart';

class ProductListScreen extends StatefulWidget {
  final List initialProducts;
  const ProductListScreen({super.key, required this.initialProducts});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final String baseUrl = AppConstants.baseUrl;
  final String ck = AppConstants.ck;
  final String cs = AppConstants.cs;

  final Color darkGreen = const Color(0xFF1B5E20);

  bool isAdminLoggedIn = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _adminPasswordController =
      TextEditingController();

  List products = [];
  List fullProductsList = [];
  Map<String, Map<String, dynamic>> _firestoreStocks = {};
  StreamSubscription? _stockStream;
  Set<String> existingFirestoreIds = {};
  bool isLoading = false;
  bool isBackgroundLoading = false;
  int page = 1;
  bool hasMore = true;
  late TabController _tabController;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _barcodeBuffer = "";
  String selectedShop = "Cassia";
  final TextEditingController _ipController = TextEditingController();

  String _activeFilter = "All";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _setupStockStream();
    _loadSavedEmail();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent * 0.95 &&
          hasMore &&
          !isLoading &&
          isAdminLoggedIn) {
        fetchProducts();
      }
    });
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adminEmailController.text = prefs.getString('saved_admin_email') ?? "";
    });
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_admin_email', email);
  }

  Future<void> _handleAdminLogin() async {
    if (_adminEmailController.text.isEmpty ||
        _adminPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both Email and Password")),
      );
      return;
    }
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _adminEmailController.text.trim(),
        password: _adminPasswordController.text.trim(),
      );
      if (mounted) Navigator.pop(context);
      if (userCredential.user != null) {
        await _saveEmail(_adminEmailController.text.trim());
        setState(() {
          isAdminLoggedIn = true;
          _adminPasswordController.clear();
        });
        fetchProducts(isInitial: true);
        _fetchAllProductsInBackground();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Login Failed: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _setupStockStream() {
    _stockStream = FirebaseFirestore.instance
        .collection('products_data')
        .snapshots()
        .listen((snapshot) {
          Map<String, Map<String, dynamic>> freshData = {};
          for (var doc in snapshot.docs) {
            freshData[doc.id] = doc.data();
          }
          if (mounted) {
            setState(() {
              _firestoreStocks = freshData;
              existingFirestoreIds = freshData.keys.toSet();
            });
          }
        });
  }

  String _getEffectiveStock(Map p, String key) {
    String id = p['id'].toString();
    if (_firestoreStocks.containsKey(id)) {
      return _firestoreStocks[id]![key]?.toString() ?? "0";
    }
    List meta = p['meta_data'] ?? [];
    var found = meta.firstWhere((m) => m['key'] == key, orElse: () => null);
    return found != null ? found['value'].toString() : "0";
  }

  Future<void> _fetchAllProductsInBackground() async {
    if (isBackgroundLoading) return;
    if (mounted) setState(() => isBackgroundLoading = true);
    List allFetched = [];
    int currentPage = 1;
    bool moreToFetch = true;
    try {
      while (moreToFetch) {
        String url =
            "$baseUrl/products?consumer_key=$ck&consumer_secret=$cs&per_page=100&page=$currentPage";
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          List data = json.decode(response.body);
          if (data.isEmpty) {
            moreToFetch = false;
          } else {
            allFetched.addAll(data);
            currentPage++;
            if (allFetched.length >= 2000) moreToFetch = false;
          }
        } else {
          moreToFetch = false;
        }
      }
      if (mounted) {
        setState(() {
          fullProductsList = allFetched;
          isBackgroundLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isBackgroundLoading = false);
    }
  }

  Future<void> fetchProducts({bool isInitial = false}) async {
    if (isLoading) return;
    if (mounted) setState(() => isLoading = true);
    if (isInitial) {
      page = 1;
      hasMore = true;
    }
    String searchPart = _searchController.text.isNotEmpty
        ? "&search=${_searchController.text}"
        : "";
    String url =
        "$baseUrl/products?consumer_key=$ck&consumer_secret=$cs&per_page=50&page=$page$searchPart";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        List fetched = json.decode(response.body);
        if (mounted) {
          setState(() {
            if (isInitial) products.clear();
            if (fetched.length < 50) hasMore = false;
            products.addAll(fetched);
            page++;
          });
        }
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _stockStream?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _ipController.dispose();
    _searchFocusNode.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!isAdminLoggedIn) return _buildAdminLoginUI();

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (_barcodeBuffer.trim().isNotEmpty) {
              setState(() {
                _searchController.text = _barcodeBuffer.trim();
                _barcodeBuffer = "";
              });
              fetchProducts(isInitial: true);
              _searchFocusNode.requestFocus();
            }
          } else if (event.character != null) {
            _barcodeBuffer += event.character!;
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: darkGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            "Suhada POS - $selectedShop",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            indicatorColor: Colors.yellow,
            tabs: const [
              Tab(text: "All", icon: Icon(Icons.list)),
              Tab(text: "Re-Order", icon: Icon(Icons.warning_amber)),
              Tab(text: "Out", icon: Icon(Icons.not_interested)),
              Tab(text: "Finance", icon: Icon(Icons.analytics)),
            ],
          ),
          actions: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .snapshots(),
              builder: (context, snapshot) {
                int notificationCount = 0;
                if (snapshot.hasData) {
                  notificationCount = snapshot.data!.docs.length;
                }

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none, size: 28),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationPanel(),
                        ),
                      ),
                    ),
                    if (notificationCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: darkGreen, width: 1),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$notificationCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, size: 28),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddProductScreen(),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: _buildDrawer(),
        body: Column(
          children: [
            _buildLiveSalesDashboard(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[100],
                  hintText: "Scan Barcode or Search Products...",
                  prefixIcon: Icon(Icons.search, color: darkGreen),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => fetchProducts(isInitial: true),
              ),
            ),
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip("All", Icons.all_inclusive),
                  _buildFilterChip("No Barcode", Icons.barcode_reader),
                  _buildFilterChip("No Shop Price", Icons.no_sim_outlined),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMainProductView("All"),
                  _buildMainProductView("Reorder"),
                  _buildMainProductView("Out"),
                  _buildFinanceQuickLinks(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: darkGreen,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderScreen(
                allProducts: fullProductsList.isNotEmpty
                    ? fullProductsList
                    : products,
                baseUrl: baseUrl,
                ck: ck,
                cs: cs,
                selectedShop: selectedShop,
              ),
            ),
          ),
          child: const Icon(Icons.shopping_cart_checkout, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDrawer() => Drawer(
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: darkGreen),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory, color: Colors.white, size: 40),
                    SizedBox(height: 10),
                    Text(
                      "Suhada POS",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.notification_important,
                  color: Colors.red,
                ),
                title: const Text("Stock Alerts"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationPanel(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.refresh, color: darkGreen),
                title: const Text("Sync Products"),
                onTap: () => fetchProducts(isInitial: true),
              ),
              ListTile(
                leading: Icon(Icons.sync_alt, color: darkGreen),
                title: const Text("Stock Update"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockUpdateScreen()),
                ),
              ),
              ListTile(
                leading: Icon(Icons.local_shipping, color: darkGreen),
                title: const Text("Order Request"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderRequestScreen(allProducts: products),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.account_balance_wallet, color: darkGreen),
                title: const Text("Credit Management"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerListScreen()),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text(
            "Logout Admin",
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: () {
            Navigator.pop(context);
            setState(() => isAdminLoggedIn = false);
          },
        ),
        const SizedBox(height: 10),
      ],
    ),
  );

  Widget _buildLiveSalesDashboard() {
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('date', isEqualTo: todayStr)
          .snapshots(),
      builder: (context, salesSnapshot) {
        double cassiaTotal = 0;
        double battistiniTotal = 0;
        if (salesSnapshot.hasData) {
          for (var doc in salesSnapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            double total =
                double.tryParse(
                  data['total_sales']?.toString() ??
                      data['total']?.toString() ??
                      '0',
                ) ??
                0;
            if (data['shop'] == 'Cassia') cassiaTotal += total;
            if (data['shop'] == 'Battistini') battistiniTotal += total;
          }
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          decoration: BoxDecoration(
            color: darkGreen,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25),
            ),
          ),
          child: Row(
            children: [
              _buildSalesCard("CASSIA SALES", cassiaTotal, Icons.storefront),
              const SizedBox(width: 10),
              _buildSalesCard("BATTISTINI SALES", battistiniTotal, Icons.store),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSalesCard(String label, double amount, IconData icon) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.yellow[700], size: 24),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "€${amount.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _buildFilterChip(String label, IconData icon) {
    bool isSelected = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
        avatar: Icon(
          icon,
          size: 16,
          color: isSelected ? Colors.white : darkGreen,
        ),
        backgroundColor: Colors.grey[200],
        selectedColor: darkGreen,
        onSelected: (val) =>
            setState(() => _activeFilter = val ? label : "All"),
      ),
    );
  }

  Widget _buildMainProductView(String tabFilter) {
    List filteredList = products;
    if (tabFilter == "Reorder") {
      filteredList = products.where((p) {
        int cassia = int.tryParse(_getEffectiveStock(p, 'cassia_stock')) ?? 0;
        int battistini =
            int.tryParse(_getEffectiveStock(p, 'battistini_stock')) ?? 0;
        return (cassia + battistini) <= 15;
      }).toList();
    } else if (tabFilter == "Out") {
      filteredList = products.where((p) {
        int cassia = int.tryParse(_getEffectiveStock(p, 'cassia_stock')) ?? 0;
        int battistini =
            int.tryParse(_getEffectiveStock(p, 'battistini_stock')) ?? 0;
        return (cassia == 0 && battistini == 0);
      }).toList();
    }

    return RefreshIndicator(
      color: darkGreen,
      onRefresh: () async => await fetchProducts(isInitial: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: filteredList.length + (isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == filteredList.length) {
            return const Center(child: CircularProgressIndicator());
          }
          var p = filteredList[index];
          String sellingPrice = _getEffectiveStock(p, 'shop_price');
          if (sellingPrice == "0") sellingPrice = p['price'].toString();
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading: _buildProductImage(
                (p['images'] != null && p['images'].isNotEmpty)
                    ? p['images'][0]['src']
                    : "",
              ),
              title: Text(
                p['name'] ?? "No Name",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "Price: €$sellingPrice | Stock: ${_getEffectiveStock(p, 'cassia_stock')} (C) | ${_getEffectiveStock(p, 'battistini_stock')} (B)",
              ),
              trailing: Icon(Icons.edit_note, color: darkGreen),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductDetailsScreen(product: p),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductImage(String url) => Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey[100],
    ),
    child: url.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => const Icon(Icons.image),
            ),
          )
        : const Icon(Icons.image),
  );

  Widget _buildFinanceQuickLinks() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _financeCard(
        "Cassia Branch",
        Icons.store,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BranchFinanceScreen(branchName: "Cassia"),
          ),
        ),
      ),
      _financeCard(
        "Battistini Branch",
        Icons.storefront,
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BranchFinanceScreen(branchName: "Battistini"),
          ),
        ),
      ),
      _financeCard(
        "Manage Bills",
        Icons.receipt_long,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BillManagementScreen()),
        ),
      ),
    ],
  );

  Widget _financeCard(String title, IconData icon, VoidCallback onTap) => Card(
    child: ListTile(
      leading: Icon(icon, color: darkGreen),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: onTap,
    ),
  );

  Widget _buildAdminLoginUI() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [darkGreen, Colors.black],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 35),
            child: Column(
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  size: 90,
                  color: Colors.white,
                ),
                const SizedBox(height: 10),
                const Text(
                  "SUHADA INVENTORY",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 50),
                TextField(
                  controller: _adminEmailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _loginInputDecoration(
                    "Email",
                    Icons.email_outlined,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _adminPasswordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _loginInputDecoration(
                    "Password",
                    Icons.lock_outline,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow[700],
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _handleAdminLogin,
                  child: const Text("UNFOLD ADMIN PANEL"),
                ),
                const SizedBox(height: 20),
                // 🔔 මෙන්න අලුතින් එකතු කරපු Button එක
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.greenAccent),
                    foregroundColor: Colors.greenAccent,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text("MANAGE BILLS"),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BillManagementScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueAccent),
                    foregroundColor: Colors.blueAccent,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  icon: const Icon(Icons.mobile_friendly),
                  label: const Text("MOBILE ORDERS"),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobileOrderScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text("CONTINUE AS CASHIER (POS)"),
                  onPressed: _showInitialSetupDialog,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _loginInputDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(15),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.yellow[700]!),
          borderRadius: BorderRadius.circular(15),
        ),
      );

  void _showInitialSetupDialog() async {
    final prefs = await SharedPreferences.getInstance();
    _ipController.text = prefs.getString('printer_ip') ?? "";
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("POS Quick Setup"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedShop,
              items: [
                "Cassia",
                "Battistini",
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => setState(() => selectedShop = val!),
              decoration: const InputDecoration(
                labelText: "Select Shop",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: "Printer IP",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: darkGreen),
            onPressed: () async {
              await prefs.setString('printer_ip', _ipController.text);
              await PrinterManager.connect(_ipController.text);

              if (!context.mounted) return;

              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderScreen(
                    allProducts: fullProductsList.isNotEmpty
                        ? fullProductsList
                        : products,
                    baseUrl: baseUrl,
                    ck: ck,
                    cs: cs,
                    selectedShop: selectedShop,
                  ),
                ),
              );
            },
            child: const Text(
              "START POS",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
