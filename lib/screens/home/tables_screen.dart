import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../../services/kot_notification_service.dart';
import '../../utils/debouncer.dart';
import '../kot/kot_tracking_screen.dart';
import '../order/order_summary_screen.dart';
import '../order/menu_screen.dart';
import '../order/takeaway_list_screen.dart';
import 'package:intl/intl.dart';
import '../../services/report_service.dart';
import '../../models/menu_item.dart';
import '../../widgets/cart_view_content.dart';

class TablesScreen extends StatefulWidget {
  final bool isTab;
  const TablesScreen({super.key, this.isTab = false});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _currentIndex = 1; // Default to Tables tab on mobile
  final KotNotificationService _kotService = KotNotificationService();
  
  // State for 3-column layout
  String? _selectedTableId;
  String? _selectedTableName;
  Map<String, dynamic>? _selectedOrderData;
  String? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedTableSection;
  
  List<MenuItem>? _cachedItems;
  List<String>? _cachedCategories;
  bool _isMenuLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1); // Default to Tables
    _currentIndex = 1; 
    _fetchMenuData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _fetchMenuData({bool force = false}) async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;

    try {
      final catsSnap = await _firestore.collection('menu_categories')
          .where('restaurantId', isEqualTo: restaurantId)
          .get();
      final itemsSnap = await _firestore.collection('menu_items')
          .where('restaurantId', isEqualTo: restaurantId)
          .get();
          
      setState(() {
        _cachedCategories = catsSnap.docs.map((d) => d['name'].toString()).toList();
        _cachedItems = itemsSnap.docs.map((doc) => MenuItem.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
        _isMenuLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isMenuLoading = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId != null && !kIsWeb) {
      _kotService.startListening(restaurantId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;
    final restaurantName = auth.restaurantName ?? "YUG POS";

    if (restaurantId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE7FF12))),
      );
    }
    
    // Safety check for TabController during Hot Reload or dynamic builds
    if (widget.isTab && _tabController == null) {
      _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        if (isWide) {
          final content = Row(
            children: [
              // 1. TABLE ZONE (Left)
              Container(
                width: 300,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
                ),
                child: _buildTableZone(restaurantId, isWide: true),
              ),
              
              // 2. ITEMS ZONE (Center)
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildCategoryButtons(),
                    _buildSearchBar(),
                    Expanded(child: _buildItemsZone(restaurantId, true)),
                  ],
                ),
              ),

              // 3. CART ZONE (Right)
              Container(
                width: 350,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
                ),
                child: _buildCartZone(restaurantId),
              ),
            ],
          );

          if (widget.isTab) return content;

          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              title: Text("${restaurantName.toUpperCase()} (WAITER)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              actions: [
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetchMenuData(force: true)),
                IconButton(icon: const Icon(Icons.logout), onPressed: () => auth.logout()),
                const SizedBox(width: 8),
              ],
            ),
            body: content,
          );
        }


        if (widget.isTab) {
          return Column(
            children: [
              TabBar(
                controller: _tabController!,
                labelColor: const Color(0xFFE7FF12),
                unselectedLabelColor: Colors.white54,
                indicatorColor: const Color(0xFFE7FF12),
                tabs: const [
                  Tab(text: 'Menu', icon: Icon(Icons.grid_view, size: 20)),
                  Tab(text: 'Tables', icon: Icon(Icons.table_bar, size: 20)),
                ],
              ),
              Expanded(
                child: Stack(
                  children: [
                    TabBarView(
                      controller: _tabController!,
                      children: [
                        Column(
                          children: [
                            _buildCategoryButtons(),
                            _buildSearchBar(),
                            Expanded(child: _buildItemsZone(restaurantId, false)),
                          ],
                        ),
                        _buildTableZone(restaurantId, isWide: false),
                      ],
                    ),
                    _buildFloatingCartDrawer(),
                  ],
                ),
              ),
            ],
          );
        }

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(restaurantName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetchMenuData(force: true)),
            ],
          ),
          drawer: _buildDrawer(restaurantName, auth),
          body: Stack(
            children: [
              IndexedStack(
                index: _currentIndex,
                children: [
                  Column(
                    children: [
                      _buildCategoryButtons(),
                      _buildSearchBar(),
                      Expanded(child: _buildItemsZone(restaurantId, false)),
                    ],
                  ),
                  _buildTableZone(restaurantId, isWide: false),
                ],
              ),
              _buildFloatingCartDrawer(),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (val) => setState(() => _currentIndex = val),
            backgroundColor: const Color(0xFF1A1A1A),
            selectedItemColor: const Color(0xFFE7FF12),
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Menu'),
              BottomNavigationBarItem(icon: Icon(Icons.table_bar), label: 'Tables'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer(String restaurantName, AuthService auth) {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFFE7FF12)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.restaurant_menu, size: 40, color: Colors.black),
                  const SizedBox(height: 8),
                  Text(restaurantName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  const Text("WAITER DASHBOARD", style: TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.receipt, color: Colors.white70),
            title: const Text("KOT Tracking", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const KotTrackingScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_bag, color: Colors.white70),
            title: const Text("Takeaway / Delivery", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TakeawayListScreen()));
            },
          ),
          const Spacer(),
          const Divider(color: Colors.white10),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
            onTap: () => auth.logout(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- REUSABLE COMPONENTS ---

  Widget _buildOrderTypeSelector() {
    final cart = context.watch<CartProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SegmentedButton<OrderType>(
        segments: const [
          ButtonSegment(value: OrderType.dineIn, label: Text("Dine-In", style: TextStyle(fontSize: 11)), icon: Icon(Icons.restaurant, size: 16)),
          ButtonSegment(value: OrderType.takeaway, label: Text("Takeaway", style: TextStyle(fontSize: 11)), icon: Icon(Icons.shopping_bag, size: 16)),
          ButtonSegment(value: OrderType.delivery, label: Text("Delivery", style: TextStyle(fontSize: 11)), icon: Icon(Icons.delivery_dining, size: 16)),
        ],
        selected: {cart.orderType},
        onSelectionChanged: (Set<OrderType> newSelection) {
          cart.setOrderType(newSelection.first);
          if (newSelection.first != OrderType.dineIn) {
             _selectedTableId = null;
             _selectedOrderData = null;
          }
          setState(() {});
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: const Color(0xFF1A1A1A),
          selectedBackgroundColor: const Color(0xFFE7FF12),
          selectedForegroundColor: Colors.black,
          side: const BorderSide(color: Colors.white10),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _buildTableZone(String restaurantId, {required bool isWide}) {
    final cart = context.watch<CartProvider>();
    
    return Column(
      children: [
        _buildOrderTypeSelector(),
        if (cart.orderType != OrderType.dineIn)
           Expanded(
             child: Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(cart.orderType == OrderType.takeaway ? Icons.shopping_bag : Icons.delivery_dining, size: 64, color: const Color(0xFFE7FF12).withOpacity(0.5)),
                   const SizedBox(height: 16),
                   Text("START NEW ${cart.orderType.name.toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                   const SizedBox(height: 24),
                   ElevatedButton.icon(
                     onPressed: () => cart.orderType == OrderType.takeaway ? _showStartTakeawayDialog() : _showStartDeliveryDialog(),
                     icon: const Icon(Icons.add),
                     label: Text("NEW ${cart.orderType.name.toUpperCase()} ORDER"),
                     style: ElevatedButton.styleFrom(
                       backgroundColor: const Color(0xFFE7FF12),
                       foregroundColor: Colors.black,
                       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     ),
                   ),
                 ],
               ),
             ),
           )
        else
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('tables').where('restaurantId', isEqualTo: restaurantId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final tables = snapshot.data!.docs
                    .map((doc) => TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                    .toList();

                // Extract unique sections (Floors)
                final floorSections = tables.map((t) => (t.section ?? 'General').trim()).toSet().toList();
                floorSections.sort();

                // Auto-select first section if none selected
                if (_selectedTableSection == null && floorSections.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedTableSection == null) {
                      setState(() => _selectedTableSection = floorSections.first);
                    }
                  });
                }

                final displayTables = _selectedTableSection == null 
                  ? tables 
                  : tables.where((t) => (t.section ?? 'General').trim() == _selectedTableSection).toList();

                return Column(
                  children: [
                    // Section (Floor) Selector
                    if (floorSections.isNotEmpty)
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: floorSections.length,
                          itemBuilder: (context, index) {
                            final section = floorSections[index];
                            final isSelected = _selectedTableSection == section;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: ChoiceChip(
                                label: Text(section.toUpperCase(), 
                                  style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                                selected: isSelected,
                                selectedColor: const Color(0xFFE7FF12),
                                backgroundColor: const Color(0xFF2A2A2A),
                                visualDensity: VisualDensity.compact,
                                onSelected: (val) => setState(() => _selectedTableSection = section),
                              ),
                            );
                          },
                        ),
                      ),
                    const Divider(color: Colors.white10),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isWide ? 2 : 4,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: displayTables.length,
                        itemBuilder: (context, index) {
                    final table = displayTables[index];
                    final isSelected = _selectedTableId == table.id;
                    final isOccupied = table.status != TableStatus.available;

                    return GestureDetector(
                      onTap: () => _handleTableSelect(table),
                      child: Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFE7FF12).withOpacity(0.1) : const Color(0xFF252525),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFE7FF12) : (isOccupied ? Colors.green.withOpacity(0.5) : Colors.white10),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(table.name, style: TextStyle(color: isSelected ? const Color(0xFFE7FF12) : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 2),
                                FittedBox(
                                  child: Text(isOccupied ? "OCCUPIED" : "AVAILABLE", 
                                    style: TextStyle(color: isOccupied ? Colors.green : Colors.grey, fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          if (isOccupied && table.currentOrderId != null)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => _promptClearTable(table.id, table.currentOrderId!),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.8),
                                    borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomLeft: Radius.circular(8)),
                                  ),
                                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  ],
);
}

  void _handleTableSelect(TableModel table) async {
    setState(() {
      _selectedTableId = table.id;
      _selectedTableName = table.name;
    });

    if (table.status != TableStatus.available && table.currentOrderId != null) {
      final doc = await _firestore.collection('orders').doc(table.currentOrderId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _selectedOrderData = data;
          _selectedOrderData!['id'] = doc.id;
        });
        
        // Sync CartProvider for mobile view
        final cart = context.read<CartProvider>();
        cart.setTable(_selectedTableId!, table.name);
        cart.setCustomerName(data['customerName'] ?? "Walk-in");
        
        final items = data['items'] as List<dynamic>? ?? [];
        for (var itemData in items) {
          final menuItemIdx = _cachedItems?.indexWhere((i) => i.name == itemData['name']) ?? -1;
          if (menuItemIdx >= 0) {
             cart.addItem(_cachedItems![menuItemIdx], quantity: itemData['quantity'] ?? 1);
          }
        }

        // Auto-navigate to Menu
        if (MediaQuery.of(context).size.width < 1000) {
          if (widget.isTab) {
            _tabController?.animateTo(0);
          } else {
            setState(() => _currentIndex = 0);
          }
        }
      }
    } else {
      setState(() => _selectedOrderData = null);
      final cart = context.read<CartProvider>();
      cart.setTable(_selectedTableId!, table.name);
      cart.clearCart();
      cart.setCustomerName("Walk-in");
      if (MediaQuery.of(context).size.width < 1000) {
        if (widget.isTab) {
           _tabController?.animateTo(0);
        } else {
           setState(() => _currentIndex = 0); // Switch to Menu
        }
      }
    }
  }



  Widget _buildCategoryButtons() {
    final categories = _cachedCategories ?? [];
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          final label = index == 0 ? "All" : categories[index - 1];
          final isSelected = (_selectedCategory ?? "All") == label;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 12)),
              selected: isSelected,
              selectedColor: const Color(0xFFE7FF12),
              backgroundColor: const Color(0xFF1E1E1E),
              onSelected: (val) => setState(() => _selectedCategory = label == "All" ? null : label),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Search items...",
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
          fillColor: const Color(0xFF1A1A1A),
          filled: true,
          contentPadding: const EdgeInsets.all(0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
        onChanged: (val) => setState(() {}),
      ),
    );
  }

  Widget _buildItemsZone(String restaurantId, bool isWide) {
    if (_isMenuLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE7FF12)));
    
    final items = _cachedItems?.where((item) {
      final matchesSearch = item.name.toLowerCase().contains(_searchController.text.toLowerCase());
      final matchesCat = _selectedCategory == null || item.category == _selectedCategory;
      return matchesSearch && matchesCat;
    }).toList() ?? [];

    int crossAxisCount = isWide ? 5 : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        bool isInCart = false;
        int qty = 0;
        
        final cart = context.watch<CartProvider>();
        final cartIdx = cart.items.indexWhere((i) => i.item.id == item.id);
        if (cartIdx >= 0) {
          isInCart = true;
          qty = cart.items[cartIdx].quantity;
        }

        return GestureDetector(
          onTap: () => _addItemToCart(item),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isInCart ? const Color(0xFFE7FF12) : Colors.white10, width: isInCart ? 2 : 1),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: item.imageUrl != null ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: Image.network(item.imageUrl!, fit: BoxFit.cover)) : const Icon(Icons.fastfood, color: Colors.white24)),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text("₹${item.price.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFE7FF12), fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (qty > 0)
                  Positioned(
                    top: 4, right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFFE7FF12), shape: BoxShape.circle),
                      child: Text("$qty", style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStartTakeawayDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Start New Takeaway?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("This will start a new takeaway order.", style: TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final cart = context.read<CartProvider>();
              cart.setOrderType(OrderType.takeaway);
              cart.setCustomerName("Takeaway");
              if (MediaQuery.of(context).size.width < 1000) {
                if (widget.isTab) {
                   _tabController?.animateTo(0);
                } else {
                   setState(() => _currentIndex = 0); 
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showStartDeliveryDialog() {
    final addressController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Start New Delivery?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter delivery details:", style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Delivery Address (Required)", labelStyle: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              final address = addressController.text.trim();
              if (address.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Address is required"), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context);
              final cart = context.read<CartProvider>();
              cart.setOrderType(OrderType.delivery);
              cart.setCustomerName("Delivery Customer");
              if (MediaQuery.of(context).size.width < 1000) {
                if (widget.isTab) {
                   _tabController?.animateTo(0);
                } else {
                   setState(() => _currentIndex = 0); 
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _addItemToCart(MenuItem item) {
    final cart = context.read<CartProvider>();
    if (cart.orderType == OrderType.dineIn && _selectedTableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a table first")));
      if (MediaQuery.of(context).size.width < 1000) {
        setState(() => _currentIndex = 1); // Switch to Tables on mobile
      }
      return;
    }
    if (_selectedTableId != null) cart.setTable(_selectedTableId!, _selectedTableName ?? "Table");
    cart.addItem(item);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added ${item.name}"), duration: const Duration(milliseconds: 500)));
  }

  Widget _buildCartZone(String restaurantId) {
    final cart = context.watch<CartProvider>();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black,
          child: Row(
            children: [
              const Icon(Icons.shopping_cart, color: Color(0xFFE7FF12)),
              const SizedBox(width: 8),
              Text(
                cart.orderType == OrderType.dineIn 
                  ? (_selectedTableId != null ? "Table: $_selectedTableName" : "No Table Selected")
                  : cart.orderType.name.toUpperCase(), 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
        const Expanded(child: CartViewContent()),
      ],
    );
  }

  void _promptClearTable(String tableId, String currentOrderId) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Settle & Clear Table?", style: TextStyle(color: Colors.white)),
        content: const Text("This will finalize the bill, record the revenue, and clear the table.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              Navigator.pop(c);
              
              final doc = await _firestore.collection('orders').doc(currentOrderId).get();
              if (doc.exists) {
                final data = doc.data() as Map<String, dynamic>;
                await _recordRevenueAndUpdateStatus(currentOrderId, data);
                await ReportService.printOrderReceipt(data, currentOrderId);
              }

              await _firestore.collection('tables').doc(tableId).update({
                'status': 'available',
                'currentOrderId': null,
              });
              
              if (_selectedTableId == tableId) {
                setState(() {
                  _selectedTableId = null;
                  _selectedOrderData = null;
                });
              }
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Table Cleared & Revenue Saved!"), backgroundColor: Colors.green));
            },
            child: const Text("Settle & Clear"),
          ),
        ],
      ),
    );
  }

  Future<void> _recordRevenueAndUpdateStatus(String orderId, Map<String, dynamic> data) async {
    if (data['status'] == 'completed' || data['status'] == 'paid') return;
    
    final restaurantId = data['restaurantId'];
    final total = (data['totalAmount'] as num).toDouble();
    
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final collRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");
    
    await _firestore.runTransaction((transaction) async {
      final collDoc = await transaction.get(collRef);
      
      Map<String, dynamic> updates = {
        'netCollection': FieldValue.increment(total),
        'grossCollection': FieldValue.increment(total),
        'billCount': FieldValue.increment(1),
        'tableCollection': FieldValue.increment(total),
        'tableCount': FieldValue.increment(1),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (!collDoc.exists) {
        updates['restaurantId'] = restaurantId;
        updates['netCollection'] = total;
        updates['grossCollection'] = total;
        updates['billCount'] = 1;
        updates['tableCollection'] = total;
        updates['tableCount'] = 1;
        transaction.set(collRef, updates);
      } else {
        transaction.update(collRef, updates);
      }
    });

    await _firestore.collection('orders').doc(orderId).update({
      'status': 'completed',
    });
  }

  Widget _buildFloatingCartDrawer() {
    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        if (cart.items.isEmpty) return const SizedBox.shrink();

        return DraggableScrollableSheet(
          initialChildSize: 0.1,
          minChildSize: 0.1,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.1, 0.95],
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE7FF12).withOpacity(0.15), width: 1),
              ),
              child: CartViewContent(isBottomSheet: true, scrollController: scrollController),
            );
          },
        );
      },
    );
  }
}
