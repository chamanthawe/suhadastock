import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'action_buttons_grid.dart';
import 'after_pay_screen.dart';
import 'calculator_screen.dart';
import 'cart_view_widget.dart';
import 'case_break_overlay.dart';
import 'case_management_service.dart';
import 'low_stock_alert_widget.dart';
import 'offline_overlay_widget.dart';
import 'orderscreen_setting.dart';
import 'payment_dialog.dart';
import 'printer_manager.dart';
import 'quick_product_grid.dart';
import 'receipt_service.dart';
import 'search_overlay_widget.dart';
import 'time_sync.dart';

List<Map<String, dynamic>> globalCart = [];
double globalDiscount = 0;
List<Map<String, dynamic>> heldCart = [];
double heldDiscount = 0;

class OrderScreen extends StatefulWidget {
  final List allProducts;
  final String baseUrl, ck, cs;
  final String selectedShop;

  const OrderScreen({
    super.key,
    required this.allProducts,
    required this.baseUrl,
    required this.ck,
    required this.cs,
    required this.selectedShop,
  });

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Map<String, Map<String, dynamic>> _localProductCache = {};
  StreamSubscription<QuerySnapshot>? _productsSubscription;
  bool _isLoadingProducts = true;

  bool _isOnline = true;
  bool _isCheckingConnectivity = false;
  Timer? _connectivityTimer;

  List<Map<String, dynamic>?> quickProducts = List.filled(50, null);
  Map<String, List<Map<String, dynamic>?>> categoryQuickItems = {
    "Short Eats": List.filled(6, null),
    "Quick Product": List.filled(18, null),
    "Fish": List.filled(6, null),
  };

  double totalValue = 0;
  double totalProfit = 0;
  int _rawInput = 0;
  bool _isPriceMode = false;
  bool _showSecretProfit = false;
  bool _isRefreshingStock = false;

  Map<String, dynamic>? _lowStockProduct;
  int _lowStockValue = 0;

  final FocusNode _barcodeFocusNode = FocusNode();
  String _barcodeBuffer = "";
  final ScrollController _cartScrollController = ScrollController();

  List _searchResults = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color accentGreen = const Color(0xFF43A047);
  final Color lightGreenBg = const Color(0xFFF1F8E9);

  bool _showCaseBreakButton = false;
  Map<String, dynamic>? _detectedCaseProduct;
  final CaseManagementService _caseService = CaseManagementService();

  @override
  void initState() {
    super.initState();
    TimeSync().init(
      url: widget.baseUrl,
      key: widget.ck,
      secret: widget.cs,
      shop: widget.selectedShop,
    );
    _startConnectivityCheck();
    _startFirestoreLiveSync();
    _loadQuickProducts();
    _loadCategorySettings();
    _calculateTotal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocusNode);
    });
  }

  void _startConnectivityCheck() {
    _connectivityTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    if (_isCheckingConnectivity) return;
    try {
      final response = await http
          .get(Uri.parse('https://google.com'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        if (!_isOnline) setState(() => _isOnline = true);
      } else {
        if (_isOnline) setState(() => _isOnline = false);
      }
    } catch (_) {
      if (_isOnline) setState(() => _isOnline = false);
    }
  }

  void _playErrorSound() async {
    try {
      await _audioPlayer.play(AssetSource('error.mp3'));
      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint("Sound Play Error: $e");
    }
  }

  void _holdCurrentCart() {
    if (globalCart.isEmpty) return;
    setState(() {
      heldCart = List.from(globalCart);
      heldDiscount = globalDiscount;
      globalCart.clear();
      globalDiscount = 0;
      _calculateTotal();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Cart Held Successfully!"),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _recallCart() {
    if (heldCart.isEmpty) return;
    setState(() {
      globalCart.addAll(heldCart);
      globalDiscount += heldDiscount;
      heldCart.clear();
      heldDiscount = 0;
      _calculateTotal();
    });
    _scrollToBottom();
  }

  void _startFirestoreLiveSync() {
    _productsSubscription = FirebaseFirestore.instance
        .collection('products_data')
        .snapshots()
        .listen((snapshot) {
          Map<String, Map<String, dynamic>> tempMap = {};
          for (var doc in snapshot.docs) {
            var data = doc.data();
            var productInfo = {
              'id': doc.id,
              'name': data['name'] ?? "Unknown",
              'price': data['shop_price']?.toString() ?? "0.00",
              'discount_price': data['discount_price']?.toString() ?? "0.00",
              'sku': data['sku']?.toString().trim() ?? "",
              'barcode': data['barcode']?.toString().trim() ?? "",
              'profit': data['profit']?.toString() ?? "0.0",
              'battistini_stock': data['battistini_stock'] ?? 0,
              'cassia_stock': data['cassia_stock'] ?? 0,
              'image': data['image'] ?? "",
              'is_case_product': data['is_case_product'] ?? false,
              'linked_single_product_id':
                  data['linked_single_product_id'] ?? "",
              'items_per_case': data['items_per_case'] ?? 12,
              'is_weighted': data['is_weighted'] ?? false,
            };
            if (productInfo['sku'] != "")
              tempMap[productInfo['sku']!] = productInfo;
            if (productInfo['barcode'] != "")
              tempMap[productInfo['barcode']!] = productInfo;
            tempMap[doc.id] = productInfo;
          }
          if (mounted) {
            setState(() {
              _localProductCache = tempMap;
              _isLoadingProducts = false;
            });
            _calculateTotal();
          }
        });
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _productsSubscription?.cancel();
    _barcodeFocusNode.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    _cartScrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        KeyboardListener(
          focusNode: _barcodeFocusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.enter) {
                _handleBarcodeScan(_barcodeBuffer);
              } else if (event.character != null) {
                _barcodeBuffer += event.character!;
              }
            }
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: Text(
                "${widget.selectedShop} POS",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              toolbarHeight: 45,
              backgroundColor: primaryGreen,
              actions: [
                IconButton(
                  icon: const Icon(Icons.menu_rounded, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderScreenSetting(
                          isRefreshing:
                              _isRefreshingStock || _isLoadingProducts,
                          onRefreshStock: _refreshAllStock,
                          baseUrl: widget.baseUrl,
                          ck: widget.ck,
                          cs: widget.cs,
                          selectedShop: widget.selectedShop,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Column(
              children: [
                _buildSearchBar(),
                Expanded(
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: CartViewWidget(
                              globalCart: globalCart,
                              heldCart: heldCart,
                              globalDiscount: globalDiscount,
                              totalValue: totalValue,
                              totalProfit: totalProfit,
                              showSecretProfit: _showSecretProfit,
                              primaryGreen: primaryGreen,
                              lightGreenBg: lightGreenBg,
                              scrollController: _cartScrollController,
                              onHoldCart: _holdCurrentCart,
                              onRecallCart: _recallCart,
                              onAddToCart: _addToCart,
                              onRemoveItem: (index) {
                                setState(() {
                                  if (globalCart[index]['qty'] > 1) {
                                    globalCart[index]['qty']--;
                                    globalCart[index]['finalPrice'] =
                                        globalCart[index]['qty'] *
                                        globalCart[index]['price'];
                                  } else {
                                    globalCart.removeAt(index);
                                  }
                                });
                                _calculateTotal();
                              },
                              onLongPressTotal: () => setState(
                                () => _showSecretProfit = !_showSecretProfit,
                              ),
                              onConfirmPrint: () => _handlePrint(),
                            ),
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildQuickGridSection(),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: _buildBottomActionSection(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SearchOverlayWidget(
                        searchResults: _searchResults,
                        primaryGreen: primaryGreen,
                        accentGreen: accentGreen,
                        getLiveStock: _getLiveStockFromCache,
                        onProductSelect: (name, product) {
                          _addToCart(name, product);
                          setState(() {
                            _searchResults = [];
                            _searchController.clear();
                          });
                          _barcodeFocusNode.requestFocus();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_showCaseBreakButton && _detectedCaseProduct != null)
          CaseBreakOverlay(
            detectedProduct: _detectedCaseProduct!,
            onBreak: _handleCaseBreakAndMove,
            onClose: () => setState(() {
              _showCaseBreakButton = false;
              _detectedCaseProduct = null;
            }),
          ),

        if (!_isOnline)
          OfflineOverlayWidget(
            isChecking: _isCheckingConnectivity,
            primaryColor: primaryGreen,
            onRetry: () async {
              setState(() => _isCheckingConnectivity = true);
              await _checkStatus();
              setState(() => _isCheckingConnectivity = false);
            },
          ),

        if (_lowStockProduct != null) ...[
          GestureDetector(
            onTap: () => setState(() => _lowStockProduct = null),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          LowStockAlertWidget(
            product: _lowStockProduct!,
            currentStock: _lowStockValue,
            onClose: () => setState(() => _lowStockProduct = null),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: primaryGreen.withValues(alpha: 0.05),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: "Search WooCommerce Store...",
          prefixIcon: Icon(Icons.search, color: primaryGreen),
          suffixIcon: _isSearching
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryGreen,
                    ),
                  ),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryGreen.withValues(alpha: 0.3)),
          ),
        ),
        onChanged: _performOnlineSearch,
      ),
    );
  }

  Widget _buildQuickGridSection() {
    return AbsorbPointer(
      absorbing: _isPriceMode,
      child: Opacity(
        opacity: _isPriceMode ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: QuickProductGrid(
            primaryGreen: primaryGreen,
            baseUrl: widget.baseUrl,
            ck: widget.ck,
            cs: widget.cs,
            onAddToCart: _addToCart,
            getLiveStock: _getLiveStockFromCache,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ActionButtonsGrid(
            primaryGreen: primaryGreen,
            accentGreen: accentGreen,
            onQuickAction: (name) => _showQuickActionPicker(name),
            onDiscount: _applyDiscount,
            onCredit: () async {
              if (globalCart.isEmpty) return;
              var result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => AfterPayScreen(
                    totalAmount: totalValue,
                    cartItems: List.from(globalCart),
                  ),
                ),
              );
              if (result == true) await _handlePrint(isCredit: true);
            },
            onClear: () {
              if (globalCart.isEmpty) return;
              setState(() {
                globalCart.clear();
                globalDiscount = 0;
              });
              _calculateTotal();
            },
            onStaff: _handleStaffOrder,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(flex: 4, child: _buildCalculatorSection()),
      ],
    );
  }

  Widget _buildCalculatorSection() {
    return CalculatorSection(
      rawInput: _rawInput,
      isPriceMode: _isPriceMode,
      primaryGreen: primaryGreen,
      lightGreenBg: lightGreenBg,
      onKeyTap: (key) {
        setState(() {
          if (key == "C") {
            _rawInput = 0;
          } else if (key == "00") {
            _rawInput = int.parse(
              "$_rawInput"
              "00",
            );
          } else {
            _rawInput = int.parse("$_rawInput$key");
          }
        });
      },
      onConfirmToggle: () {
        if (_isPriceMode && _rawInput > 0) {
          double pr = _rawInput / 100.0;
          setState(() {
            globalCart.add({
              'id': 'manual_${DateTime.now().millisecondsSinceEpoch}',
              'name': "Manual Item",
              'price': pr,
              'qty': 1.0,
              'finalPrice': pr,
              'isWeighted': false,
              'manage_stock': false,
            });
            _rawInput = 0;
            _isPriceMode = false;
          });
          _calculateTotal();
          _scrollToBottom();
        } else {
          setState(() => _isPriceMode = !_isPriceMode);
        }
      },
    );
  }

  Future<void> _handleCaseBreakAndMove() async {
    if (_detectedCaseProduct == null) return;
    String caseId = _detectedCaseProduct!['id'].toString();
    var liveData = _localProductCache[caseId] ?? _detectedCaseProduct!;
    String singleId = liveData['linked_single_product_id'].toString();
    int itemsPerCase = (liveData['items_per_case'] as num).toInt();

    if (singleId.isEmpty || singleId == "null") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No Single Product linked to this Case!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String activeBranch =
        widget.selectedShop.toLowerCase().contains("battistini")
        ? "battistini"
        : "cassia";
    int liveStock = _getLiveStockFromCache(liveData);

    if (liveStock < 1) {
      _playErrorSound();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("හදිසි දැනුම්දීමයි: Case Stock අවසන්!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool success = await _caseService.breakCaseToSingleUnits(
      caseProductId: caseId,
      singleProductId: singleId,
      itemsPerCase: itemsPerCase,
      branch: activeBranch,
    );

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Case Broken! Moved units successfully."),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _showCaseBreakButton = false;
        _detectedCaseProduct = null;
      });
    } else {
      _playErrorSound();
    }
    _barcodeFocusNode.requestFocus();
  }

  void _handleBarcodeScan(String barcode) async {
    if (_lowStockProduct != null) setState(() => _lowStockProduct = null);
    String cleanBarcode = barcode.trim().replaceAll(RegExp(r'[\n\r]'), '');
    if (cleanBarcode.isEmpty) return;

    // --- පවතින Pending Order එකක්දැයි පරීක්ෂා කිරීම (ID එක දිග නිසා මුලින්ම මෙය බලයි) ---
    if (cleanBarcode.length >= 15) {
      try {
        var pendingDoc = await FirebaseFirestore.instance
            .collection('pending_orders')
            .doc(cleanBarcode)
            .get();

        if (pendingDoc.exists) {
          var data = pendingDoc.data()!;
          List items = data['items'] ?? [];

          setState(() {
            // පවතින Cart එක Clear නොකර අලුත් items එකතු කරයි
            for (var item in items) {
              double itemPrice =
                  double.tryParse(item['price'].toString()) ?? 0.0;
              double itemQty = double.tryParse(item['qty'].toString()) ?? 1.0;

              globalCart.add({
                'id':
                    item['sku'] ??
                    'manual_${DateTime.now().millisecondsSinceEpoch}', // SKU එක ID එක ලෙස ගනී
                'name': item['name'] ?? 'No Name',
                'price': itemPrice,
                'qty': itemQty,
                'finalPrice': double.parse(
                  (itemPrice * itemQty).toStringAsFixed(2),
                ),
                'isWeighted': item['is_weighted'] ?? false,
                'sku': item['sku'] ?? "",
                'manage_stock': true,
                'image': item['image'] ?? "",
              });
            }
          });

          _calculateTotal();
          _scrollToBottom();

          // එකවරක් Scan කළ පසු Firestore එකෙන් එම Order එක ඉවත් කරයි (නැවත Scan කිරීම වැළැක්වීමට)
          await FirebaseFirestore.instance
              .collection('pending_orders')
              .doc(cleanBarcode)
              .delete();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Mobile Order Added to Cart!"),
              backgroundColor: Colors.green,
            ),
          );

          _barcodeBuffer = "";
          return; // මෙතනින් නවතියි, පහල තියෙන Product search එකට යන්නේ නැත.
        }
      } catch (e) {
        debugPrint("Pending Order Scan Error: $e");
      }
    }

    // --- සාමාන්‍ය Product Barcode Search කොටස (ඔයාගේ කලින් තිබූ code එකමයි) ---
    List<Map<String, dynamic>> matchingProducts = _localProductCache.values
        .where((p) {
          String pBarcode = p['barcode'].toString().trim();
          String pSku = p['sku'].toString().trim();
          return pBarcode == cleanBarcode ||
              pSku == cleanBarcode ||
              pSku.startsWith("$cleanBarcode-");
        })
        .toSet()
        .toList();

    if (matchingProducts.isEmpty) {
      _playErrorSound();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("හමු නොවීය: $cleanBarcode"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    } else if (matchingProducts.length == 1) {
      _addToCart(matchingProducts[0]['name'], matchingProducts[0]);
    } else {
      _showMultiProductPicker(matchingProducts);
    }
    _barcodeBuffer = "";
  }

  void _showMultiProductPicker(List<Map<String, dynamic>> products) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: primaryGreen,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.inventory_2, color: Colors.white),
              SizedBox(width: 10),
              Text(
                "Products Found",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 450,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: products.length,
            itemBuilder: (ctx, i) {
              final p = products[i];
              return ListTile(
                title: Text(p['name']),
                subtitle: Text(
                  "Price: €${p['price']} | Stock: ${_getLiveStockFromCache(p)}",
                ),
                trailing: Icon(Icons.add_circle_outline, color: primaryGreen),
                onTap: () {
                  _addToCart(p['name'], p);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    ).then((_) => _barcodeFocusNode.requestFocus());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cartScrollController.hasClients) {
        _cartScrollController.animateTo(
          _cartScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  int _getLiveStockFromCache(dynamic p) {
    if (p == null) return 0;
    String id = p['id'].toString();
    var cachedProd = _localProductCache[id];
    if (cachedProd == null) return 0;
    bool isBat = widget.selectedShop.toLowerCase().contains("battistini");
    var stockValue = isBat
        ? (cachedProd['battistini_stock'] ?? 0)
        : (cachedProd['cassia_stock'] ?? 0);
    return (double.tryParse(stockValue.toString())?.toInt() ?? 0);
  }

  void _calculateTotal() {
    double tempT = 0, tempP = 0;
    for (var item in globalCart) {
      if (item['id'].toString().contains('manual')) {
        tempT += (item['finalPrice'] as double);
        continue;
      }
      var cached = _localProductCache[item['id'].toString()];
      double normalPrice =
          double.tryParse(
            cached?['price']?.toString() ?? item['price'].toString(),
          ) ??
          0.0;
      double discountPrice =
          double.tryParse(cached?['discount_price']?.toString() ?? "0.0") ??
          0.0;
      double unitPrice = (discountPrice > 0) ? discountPrice : normalPrice;
      double unitProfit =
          double.tryParse(cached?['profit']?.toString() ?? '0.0') ?? 0.0;
      item['price'] = unitPrice;
      item['original_price'] = (discountPrice > 0) ? normalPrice : 0.0;

      // දශම 3කට සකසයි
      double currentQty = double.parse(
        (item['qty'] as double).toStringAsFixed(3),
      );
      item['finalPrice'] = double.parse(
        (currentQty * unitPrice).toStringAsFixed(2),
      );

      tempT += item['finalPrice'];
      tempP += (unitProfit * currentQty);
    }
    if (mounted) {
      setState(() {
        totalValue = double.parse(
          (tempT - globalDiscount).clamp(0, double.infinity).toStringAsFixed(2),
        );
        totalProfit = double.parse(
          (tempP - globalDiscount).clamp(0, double.infinity).toStringAsFixed(2),
        );
      });
    }
  }

  Future<void> _addToCart(String name, dynamic p) async {
    if (p == null) return;
    int liveStock = _getLiveStockFromCache(p);
    int existingIdx = globalCart.indexWhere(
      (item) => item['id'].toString() == p['id'].toString(),
    );
    double qtyInCart = (existingIdx != -1)
        ? (globalCart[existingIdx]['qty'] as double)
        : 0.0;
    bool isWeighted = _rawInput > 0;

    // Qty එක දශම 3කට සීමා කරයි
    double rawQty = isWeighted ? (_rawInput / 1000.0) : 1.0;
    double inputQty = double.parse(rawQty.toStringAsFixed(3));

    if ((qtyInCart + inputQty) > liveStock) {
      _showStockAlert();
      return;
    }

    var cached = _localProductCache[p['id'].toString()];
    double normalPrice =
        double.tryParse(
          cached?['price']?.toString() ?? p['price'].toString(),
        ) ??
        0.0;
    double discountPrice =
        double.tryParse(cached?['discount_price']?.toString() ?? "0.0") ?? 0.0;
    double unitPrice = (discountPrice > 0) ? discountPrice : normalPrice;

    String imgURL =
        (cached != null && cached['image'] != null && cached['image'] != "")
        ? cached['image'].toString()
        : (p['image'] ?? "");

    setState(() {
      if (existingIdx != -1) {
        double newQty = (globalCart[existingIdx]['qty'] as double) + inputQty;
        globalCart[existingIdx]['qty'] = double.parse(
          newQty.toStringAsFixed(3),
        );
        globalCart[existingIdx]['finalPrice'] = double.parse(
          (globalCart[existingIdx]['qty'] * unitPrice).toStringAsFixed(2),
        );
      } else {
        globalCart.add({
          'id': p['id'],
          'name': name,
          'price': unitPrice,
          'original_price': (discountPrice > 0) ? normalPrice : 0.0,
          'qty': inputQty,
          'finalPrice': double.parse((unitPrice * inputQty).toStringAsFixed(2)),
          'isWeighted': isWeighted || (p['is_weighted'] == true),
          'sku': p['sku'],
          'manage_stock': true,
          'image': imgURL,
        });
      }

      bool isCase =
          _localProductCache[p['id'].toString()]?['is_case_product'] == true;
      if (isCase) {
        _showCaseBreakButton = true;
        _detectedCaseProduct = _localProductCache[p['id'].toString()] ?? p;
      } else {
        _showCaseBreakButton = false;
        _detectedCaseProduct = null;
      }

      int updatedStockAfterAdd = liveStock - (qtyInCart + inputQty).toInt();
      if (updatedStockAfterAdd <= 15 && updatedStockAfterAdd >= 0) {
        _lowStockProduct = {
          'id': p['id'].toString(),
          'name': name,
          'image': imgURL,
        };
        _lowStockValue = updatedStockAfterAdd;
        _sendLowStockNotification(
          p['id'].toString(),
          name,
          updatedStockAfterAdd,
          imgURL,
        );
      } else {
        _lowStockProduct = null;
      }
      _rawInput = 0;
    });
    _calculateTotal();
    _scrollToBottom();
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _sendLowStockNotification(
    String productId,
    String name,
    int stock,
    String imageUrl,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(productId)
          .set({
            'productId': productId,
            'productName': name,
            'remainingStock': stock,
            'shop': widget.selectedShop,
            'imageUrl': imageUrl,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'message': '$name ඉතිරිව ඇත්තේ $stock පමණි',
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Notification Error: $e");
    }
  }

  void _performOnlineSearch(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      try {
        final String url =
            "${widget.baseUrl}/products?consumer_key=${widget.ck}&consumer_secret=${widget.cs}&search=$query&per_page=50";
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200 && mounted) {
          setState(() {
            _searchResults = json.decode(response.body);
            _isSearching = false;
          });
        }
      } catch (e) {
        setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _handleStaffOrder() async {
    if (globalCart.isEmpty) {
      _playErrorSound();
      return;
    }
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Staff Use"),
        content: const Text(
          "මෙම අයිතම Staff ලෙස සටහන් කර Stock අඩු කිරීමට අවශ්‍යද?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("නැත"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ඔව්"),
          ),
        ],
      ),
    ).then((value) => value ?? false);
    if (!confirm) return;
    try {
      final String d = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String t = DateFormat('HH:mm').format(DateTime.now());
      await FirebaseFirestore.instance.collection('staff_orders').add({
        'shop': widget.selectedShop,
        'total_value': totalValue,
        'items': List.from(globalCart),
        'date': d,
        'time': t,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await _updateWooStockFast(List.from(globalCart));
      _resetAfterOrder("Staff Order Recorded!");
    } catch (e) {
      _resetAfterOrder("Error: $e");
    }
  }

  Future<void> _handlePrint({bool isCredit = false}) async {
    if (globalCart.isEmpty) return;
    double? cashReceived;
    double balance = 0;
    bool onlyConfirmNoPrint = false;

    if (!isCredit) {
      Map<String, dynamic>? result = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PaymentDialog(
          totalValue: totalValue,
          primaryGreen: primaryGreen,
          accentGreen: accentGreen,
        ),
      );
      if (result == null) {
        _barcodeFocusNode.requestFocus();
        return;
      }
      onlyConfirmNoPrint = result['confirmOnly'] ?? false;
      cashReceived = result['cash'];
      balance = result['balance'] ?? 0;
    }

    final List<Map<String, dynamic>> finalCart = List.from(globalCart);
    if (!isCredit)
      _saveAndSyncData(finalCart, totalValue, totalProfit, globalDiscount);
    if (onlyConfirmNoPrint) {
      _resetAfterOrder("Order Saved Successfully!");
      return;
    }
    _startPrintingProcess(
      finalCart,
      totalValue,
      globalDiscount,
      isCredit,
      cashReceived ?? 0,
      balance,
    );
  }

  void _startPrintingProcess(
    List<Map<String, dynamic>> cart,
    double total,
    double discount,
    bool isCredit,
    double cash,
    double balance,
  ) async {
    try {
      String? ip = await PrinterManager.getSavedIP();
      if (ip == null) {
        _showPrintRetryDialog(
          "Printer IP Not Set!",
          cart,
          total,
          discount,
          isCredit,
          cash,
          balance,
        );
        return;
      }
      bool connected = await PrinterManager.connect(ip);
      if (connected && PrinterManager.printer != null) {
        await ReceiptService.printOrder(
          cart: cart,
          total: total,
          discount: discount,
          selectedShop: widget.selectedShop,
          isCredit: isCredit,
          cashReceived: cash,
          balance: balance,
        );
        _showPrintSuccessCheck(cart, total, discount, isCredit, cash, balance);
      } else {
        _showPrintRetryDialog(
          "Printer Offline",
          cart,
          total,
          discount,
          isCredit,
          cash,
          balance,
        );
      }
    } catch (e) {
      _showPrintRetryDialog(
        "Error: $e",
        cart,
        total,
        discount,
        isCredit,
        cash,
        balance,
      );
    }
  }

  void _showPrintSuccessCheck(cart, total, discount, isCredit, cash, balance) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Print"),
        content: const Text("බිල්පත සාර්ථකව මුද්‍රණය වූවාද?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startPrintingProcess(
                cart,
                total,
                discount,
                isCredit,
                cash,
                balance,
              );
            },
            child: const Text("RE-PRINT", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetAfterOrder("Order Completed!");
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            child: const Text(
              "YES, DONE",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrintRetryDialog(
    String error,
    cart,
    total,
    discount,
    isCredit,
    cash,
    balance,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Print Failed"),
        content: Text("$error\nOrder එක Database එකට Save වුණා."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetAfterOrder("Order Saved but Print Failed");
            },
            child: const Text("SKIP PRINT"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startPrintingProcess(
                cart,
                total,
                discount,
                isCredit,
                cash,
                balance,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            child: const Text(
              "RETRY PRINT",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _saveAndSyncData(
    List<Map<String, dynamic>> items,
    double total,
    double profit,
    double discount,
  ) async {
    final String d = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String t = DateFormat('HH:mm').format(DateTime.now());
    await FirebaseFirestore.instance.collection('orders').add({
      'shop': widget.selectedShop,
      'total_sales': total,
      'net_profit': profit,
      'discount': discount,
      'items': items,
      'date': d,
      'time': t,
      'timestamp': FieldValue.serverTimestamp(),
    });

    for (var item in items) {
      if (item['id'].toString().contains('manual')) continue;

      bool isBat = widget.selectedShop.toLowerCase().contains("battistini");
      String targetKey = isBat ? "battistini_stock" : "cassia_stock";

      var cachedItem = _localProductCache[item['id'].toString()];
      bool isWeightedProduct =
          (item['isWeighted'] == true) ||
          (item['is_weighted'] == true) ||
          (cachedItem != null && cachedItem['is_weighted'] == true);

      if (!isWeightedProduct) {
        int qtyToSync = (item['qty'] as num).toInt();
        await TimeSync().addOrder(item, qtyToSync, targetKey);
      } else {
        debugPrint(
          "Skipping WooCommerce Sync for Weighted Item: ${item['name']}",
        );
      }
    }
    _updateWooStockFast(items);
  }

  Future<void> _updateWooStockFast(List<Map<String, dynamic>> items) async {
    for (var item in items) {
      if (item['id'].toString().contains('manual')) continue;

      var cachedItem = _localProductCache[item['id'].toString()];
      bool isWeightedProduct =
          (item['isWeighted'] == true) ||
          (item['is_weighted'] == true) ||
          (cachedItem != null && cachedItem['is_weighted'] == true);

      dynamic soldQty;
      if (isWeightedProduct) {
        // බර දශම 3කට සකසා යවයි
        soldQty = double.parse(
          (item['qty'] as num).toDouble().toStringAsFixed(3),
        );
      } else {
        soldQty = (item['qty'] as num).toInt();
      }

      String targetKey =
          widget.selectedShop.toLowerCase().contains("battistini")
          ? "battistini_stock"
          : "cassia_stock";

      try {
        await FirebaseFirestore.instance
            .collection('products_data')
            .doc(item['id'].toString())
            .update({
              targetKey: FieldValue.increment(-soldQty),
              'last_updated': FieldValue.serverTimestamp(),
            });
      } catch (e) {
        debugPrint("Firestore Sync Error: $e");
      }
    }
  }

  void _resetAfterOrder(String m) {
    setState(() {
      globalCart.clear();
      globalDiscount = 0;
      totalProfit = 0;
      totalValue = 0;
      _lowStockProduct = null;
      _showCaseBreakButton = false;
      _detectedCaseProduct = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: m.contains("Failed") ? Colors.red : primaryGreen,
      ),
    );
    _barcodeFocusNode.requestFocus();
  }

  void _showStockAlert() {
    _playErrorSound();
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text("තොග අවසන්", style: TextStyle(color: Colors.red)),
        content: Text("මෙම භාණ්ඩය තොගයේ නොමැත."),
      ),
    );
  }

  Future<void> _refreshAllStock() async {
    setState(() => _isRefreshingStock = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isRefreshingStock = false);
  }

  void _applyDiscount() {
    final tc = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Discount"),
        content: TextField(
          controller: tc,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: "€ "),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            onPressed: () {
              setState(() {
                globalDiscount = double.tryParse(tc.text) ?? 0;
              });
              _calculateTotal();
              Navigator.pop(context);
            },
            child: const Text("Apply", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadQuickProducts() async {
    var doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('quick_grid')
        .get();
    if (doc.exists && mounted) {
      List d = (doc.data() as Map<String, dynamic>)['items'] ?? [];
      setState(() {
        for (int i = 0; i < d.length && i < 50; i++) {
          quickProducts[i] = d[i] != null
              ? Map<String, dynamic>.from(d[i] as Map)
              : null;
        }
      });
    }
  }

  Future<void> _loadCategorySettings() async {
    var doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('category_items')
        .get();
    if (doc.exists && mounted) {
      setState(() {
        Map<String, dynamic> data = doc.data()!;
        categoryQuickItems.forEach((key, value) {
          if (data[key] != null) {
            List rawList = data[key];
            categoryQuickItems[key] = List.filled(
              categoryQuickItems[key]!.length,
              null,
            );
            for (
              int i = 0;
              i < rawList.length && i < categoryQuickItems[key]!.length;
              i++
            ) {
              categoryQuickItems[key]![i] = rawList[i];
            }
          }
        });
      });
    }
  }

  Future<void> _saveCategorySettings() async {
    await FirebaseFirestore.instance
        .collection('settings')
        .doc('category_items')
        .set(categoryQuickItems);
  }

  void _showQuickActionPicker(String categoryName) {
    int itemCount = (categoryName == "Short Eats" || categoryName == "Fish")
        ? 6
        : 18;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                categoryName,
                style: TextStyle(
                  color: primaryGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                "Long Press to Edit",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: itemCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                var p = categoryQuickItems[categoryName]![index];
                return Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (p != null) {
                            _addToCart(p['name'], p);
                            Navigator.pop(context);
                          } else {
                            _pickProductForCategory(
                              categoryName,
                              index,
                              setDialogState,
                            );
                          }
                        },
                        onLongPress: () => _pickProductForCategory(
                          categoryName,
                          index,
                          setDialogState,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: p == null
                                  ? Colors.grey[300]!
                                  : primaryGreen,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4),
                            ],
                          ),
                          child: p == null
                              ? const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.grey,
                                  size: 30,
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: CachedNetworkImage(
                                    imageUrl: p['image'] ?? "",
                                    fit: BoxFit.cover,
                                    errorWidget: (c, u, e) => Icon(
                                      Icons.fastfood,
                                      color: primaryGreen,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      p != null ? p['name'] : "Empty",
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ).then((_) => _barcodeFocusNode.requestFocus());
  }

  void _pickProductForCategory(
    String category,
    int index,
    StateSetter setDialogState,
  ) {
    List res = [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: "Search Product...",
                  prefixIcon: Icon(Icons.search, color: primaryGreen),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) async {
                  if (v.length < 3) return;
                  final r = await http.get(
                    Uri.parse(
                      "${widget.baseUrl}/products?consumer_key=${widget.ck}&consumer_secret=${widget.cs}&search=$v&per_page=15",
                    ),
                  );
                  if (r.statusCode == 200)
                    setMState(() => res = json.decode(r.body));
                },
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: res.length,
                  itemBuilder: (ctx, i) => ListTile(
                    title: Text(res[i]['name']),
                    trailing: Icon(Icons.add, color: primaryGreen),
                    onTap: () {
                      setState(() {
                        categoryQuickItems[category]![index] = {
                          'id': res[i]['id'],
                          'name': res[i]['name'],
                          'price': res[i]['price'],
                          'image': (res[i]['images'] as List).isNotEmpty
                              ? res[i]['images'][0]['src']
                              : "",
                          'sku': res[i]['sku'],
                        };
                      });
                      _saveCategorySettings();
                      setDialogState(() {});
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
