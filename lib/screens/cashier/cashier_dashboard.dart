import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../services/usb_printer_service.dart';
import '../../models/table_model.dart';
import '../../utils/navigator_utils.dart';
import '../../services/report_service.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../utils/debouncer.dart';
import '../../widgets/order_dialog.dart';
import '../order/takeaway_list_screen.dart';
import '../order/online_orders_screen.dart'; // New import
import '../../widgets/takeaway_order_dialog.dart';
import '../../widgets/cart_view_content.dart';
import 'revenue_dashboard.dart'; 
import 'order_history_screen.dart';
import 'recent_bills_screen.dart';

class CashierDashboard extends StatefulWidget {
  const CashierDashboard({super.key});

  @override
  State<CashierDashboard> createState() => _CashierDashboardState();
}

class _CashierDashboardState extends State<CashierDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedTableId;
  Map<String, dynamic>? _selectedOrderData;
  bool _hasCreatedTempTable = false;
  String? _selectedCategory;
  final TextEditingController _itemSearchController = TextEditingController();
  final Debouncer _debouncer = Debouncer(milliseconds: 300);
  
  List<String>? _cachedCategories;
  List<MenuItem>? _cachedItems;
  bool _isMenuLoading = false;
  int _mobileTabIndex = 1;
  String _selectedOrderType = 'Dine In';
  String? _selectedTableSection;
  bool _showMidnightResetBanner = false;
  bool _isNavigating = false;

  int _getTotalCartQuantity() {
    if (_selectedOrderData == null) return 0;
    final items = _selectedOrderData!['items'] as List<dynamic>? ?? [];
    return items.fold(0, (sum, i) => sum + ((i['quantity'] as num?)?.toInt() ?? 0));
  }

  @override
  void initState() {
    super.initState();
    // Fetch menu once on first mount to avoid triggering setState inside build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final restaurantId = context.read<AuthService>().restaurantId;
      _fetchMenuData(restaurantId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;
    final restaurantName = auth.restaurantName ?? "YUG POS";
    final isMobile = MediaQuery.of(context).size.width < 1000;

    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      appBar: AppBar(
        centerTitle: true,
        title: Text("YUG POS", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {
            _fetchMenuData(restaurantId, force: true);
            setState(() {});
          }, tooltip: "Refresh Data"),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: const Color(0xFFFCDD22).withOpacity(0.1)),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 150,
                        height: 58,
                        child: Image.asset(
                          'lib/assets/img/yug-poslogo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text("YUG POS", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold, fontSize: 18)),
                    const Text("CASHIER PANEL", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Color(0xFFFCDD22)),
              title: const Text('Recent Bills'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RecentBillsScreen()));
              },
            ),
             ListTile(
               leading: const Icon(Icons.bar_chart, color: Color(0xFFFCDD22)),
              title: const Text('Revenue Dashboard'),
              onTap: () {
                safePop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RevenueDashboard()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.print, color: Colors.blueAccent),
              title: const Text('Daily Collection Print'),
              onTap: () {
                Navigator.pop(context);
                _downloadDailyCollection(restaurantId, restaurantName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Menu/Table Setup'),
              onTap: () {
                Navigator.pop(context);
                _showManagementMenu();
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_bag, color: Color(0xFFFCDD22)),
              title: const Text('Tk/Del Orders'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TakeawayListScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download, color: Colors.blueAccent),
              title: const Text('Online Orders (Z/S)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineOrdersScreen()));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () => context.read<AuthService>().logout(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: (isMobile && _selectedOrderType == 'Dine In') 
        ? BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: const Color(0xFF141615),
            selectedItemColor: const Color(0xFFFCDD22),
            unselectedItemColor: Colors.grey,
            currentIndex: _selectedOrderType == 'Dine In' ? _mobileTabIndex : 0,
            onTap: (index) {
              if (_selectedOrderType == 'Dine In') {
                setState(() => _mobileTabIndex = index);
              }
            },
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: "Menu"),
              if (_selectedOrderType == 'Dine In') 
                const BottomNavigationBarItem(icon: Icon(Icons.numbers), label: "Tables"),
            ],
          )
        : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1000;

          if (isWide) {
            return Row(
              children: [
                if (_selectedOrderType == 'Dine In') Container(
                  width: 320,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141615),
                    border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
                  ),
                  child: Column(
                    children: [
                      _buildMidnightResetBanner(restaurantId),
                      Expanded(child: _buildTableZone(restaurantId)),
                    ],
                  ),
                ),
                if (_selectedOrderType != 'Dine In')
                   const SizedBox(width: 20), // Tiny margin for cleaner layout
                Expanded(
                  flex: 3,
                  child: Container(
                    color: const Color(0xFF141615),
                    child: Column(
                      children: [
                        _buildTopControlBar(restaurantId, restaurantName),
                        Expanded(child: _buildItemsZone(restaurantId)),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 380,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141615),
                    border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
                  ),
                  child: _buildCartBillingZone(restaurantId),
                ),
              ],
            );
          } else {
            return Stack(
              children: [
                Column(
                  children: [
                    _buildMidnightResetBanner(restaurantId),
                    Expanded(
                      child: IndexedStack(
                        index: _mobileTabIndex,
                        children: [
                          _buildItemsZone(restaurantId),
                          _buildTableZone(restaurantId),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_mobileTabIndex == 0)
                  Consumer<CartProvider>(
                    builder: (context, cart, child) {
                      if (cart.items.isEmpty) return const SizedBox.shrink();
                      return DraggableScrollableSheet(
                        initialChildSize: 0.11,
                        minChildSize: 0.11,
                        maxChildSize: 0.95,
                        snap: true,
                        snapSizes: const [0.11, 0.95],
                        builder: (context, scrollController) {
                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF141615),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF141615).withOpacity(0.6), blurRadius: 15, offset: const Offset(0, -5)),
                              ],
                            ),
                            child: CartViewContent(isBottomSheet: true, scrollController: scrollController),
                          );
                        },
                      );
                    },
                  ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildTopControlBar(String? restaurantId, String restaurantName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF141615),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: TextField(
                controller: _itemSearchController,
                onChanged: (v) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: "Search menu items...",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Colors.grey, size: 18),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          _buildCollectionCounter(restaurantId),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xFFFCDD22)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecentBillsScreen())),
            tooltip: "Recent Bills",
          ),
          IconButton(
            icon: const Icon(Icons.shopping_bag, size: 20, color: Color(0xFFFCDD22)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TakeawayListScreen())),
            tooltip: "Tk/Del Orders",
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download, size: 20, color: Colors.blueAccent),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineOrdersScreen())),
            tooltip: "Online Orders (Z/S)",
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Color(0xFFFCDD22)),
            onPressed: () => _fetchMenuData(restaurantId, force: true),
            tooltip: "Refresh Data",
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineOrderBadge(String? restaurantId) {
    if (restaurantId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('orderSource', isEqualTo: 'urbanpiper')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineOrdersScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_bag, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text("$count NEW", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollectionCounter(String? restaurantId) {
    if (restaurantId == null) return const SizedBox.shrink();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
      builder: (context, snapshot) {
        double net = 0;
        double table = 0;
        double takeaway = 0;
        double delivery = 0;

        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          net = (data['netCollection'] ?? 0).toDouble();
          table = (data['tableCollection'] ?? 0).toDouble();
          takeaway = (data['takeawayCollection'] ?? 0).toDouble();
          delivery = (data['deliveryCollection'] ?? 0).toDouble();
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row( 
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatChip("Net: ₹${net.toStringAsFixed(0)}", Colors.green),
              _buildStatChip("Dine In: ₹${table.toStringAsFixed(0)}", const Color(0xFFFCDD22)),
              _buildStatChip("Tk: ₹${takeaway.toStringAsFixed(0)}", Colors.purpleAccent),
              _buildStatChip("Del: ₹${delivery.toStringAsFixed(0)}", Colors.deepOrange),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTableGrid(String? restaurantId) {
    return FutureBuilder<QuerySnapshot>(
      future: _firestore.collection('tables')
          .where('restaurantId', isEqualTo: restaurantId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final tables = snapshot.data!.docs.map((doc) => TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
        tables.sort(TableModel.compareByName);
        
        return LayoutBuilder(
          builder: (context, constraints) {
            final gridWidth = constraints.maxWidth;
            final isMobile = gridWidth < 600;
            // REQ: 4 cards on mobile
            final crossAxis = isMobile ? 4 : (gridWidth < 900 ? 5 : 8);
            final spacing = isMobile ? 6.0 : 12.0;
            final aspectRatio = isMobile ? 0.68 : 1.0;

            return GridView.builder(
              padding: EdgeInsets.all(isMobile ? 8 : 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxis,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemCount: tables.length,
              itemBuilder: (context, index) {
                return _buildTableCard(tables[index]);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTableCard(TableModel table) {
    final isOccupied = table.status != TableStatus.available;
    final gridWidth = MediaQuery.of(context).size.width;
    final isMobile = gridWidth < 1000;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOccupied ? const Color(0xFFFCDD22) : Colors.white10, width: 0.8),
        boxShadow: [
          BoxShadow(color: const Color(0xFF141615).withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: () => _handleTableSelect(table),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 100, // Fixed width for scaling reference
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(table.name, 
                    style: TextStyle(fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold), 
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  _buildUltraMiniStatus(table.status),
                  const SizedBox(height: 1),
                  if (!isMobile) ...[
                    Text("Sec: ${table.section}", style: TextStyle(color: Colors.grey[600], fontSize: 8), overflow: TextOverflow.ellipsis),
                    Text("Cap: ${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 8)),
                    const SizedBox(height: 4),
                  ] else ...[
                    Text("C:${table.capacity}", style: TextStyle(color: Colors.grey[600], fontSize: 7), textAlign: TextAlign.right),
                  ],
                  
                  const SizedBox(height: 1),
                  if (isOccupied && table.status != TableStatus.billRequested)
                    _buildUltraCompactButton("BILL", Icons.receipt_long, Colors.red, () {
                       _firestore.collection('tables').doc(table.id).update({'status': 'billRequested'});
                       if (table.currentOrderId != null) {
                         _firestore.collection('orders').doc(table.currentOrderId).update({'status': 'bill_requested'});
                       }
                    }),
                  
                  _buildUltraCompactButton(isOccupied ? "KOT" : "ORDER", isOccupied ? Icons.restaurant_menu : Icons.add_shopping_cart, isOccupied ? const Color(0xFFFCDD22) : const Color(0xFFFCDD22), () {
                    if (isOccupied && table.currentOrderId != null) {
                      _showOrderDetailPanel(table);
                    } else {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => CommonOrderDialog(table: table),
                      );
                    }
                  }),
    
                  if (isOccupied)
                    _buildUltraCompactButton("CLR", Icons.cleaning_services, Colors.grey, () => _showClearTableDialog(table)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditTableDialog(TableModel table) {
     // Generic implementation
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Edit Table functionality coming soon!")));
  }

  void _confirmDeleteTable(TableModel table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Table?"),
        content: Text("Are you sure you want to delete ${table.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _firestore.collection('tables').doc(table.id).delete();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveKotFeed(String? restaurantId) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blueGrey[900],
          child: const Row(
            children: [
              Icon(Icons.kitchen, color: Colors.white),
              SizedBox(width: 12),
              Text("LIVE KOT FEED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<QuerySnapshot>(
            future: _firestore.collection('kots')
                .where('restaurantId', isEqualTo: restaurantId)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No active KOTs", style: TextStyle(color: Colors.grey)));
              }
              
              // Filter and Sort in memory to avoid needing a complex composite index
              final kots = snapshot.data!.docs.where((doc) {
                final status = (doc.data() as Map<String, dynamic>)['status'] ?? 'Pending';
                return status != 'Served' && status != 'Done'; // Hide Completed items
              }).toList();

              // Sort by createdAt descending
              kots.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = aData['createdAt'] as Timestamp?;
                final bTime = bData['createdAt'] as Timestamp?;
                
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });

              if (kots.isEmpty) {
                return const Center(child: Text("No active KOTs", style: TextStyle(color: Colors.grey)));
              }
              
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: kots.length,
                itemBuilder: (context, index) {
                  final kot = kots[index];
                  final data = kot.data() as Map<String, dynamic>;
                  return _buildKotCard(kot.id, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKotCard(String id, Map<String, dynamic> data) {
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final status = data['status'] ?? 'Pending';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: status == 'Preparing' ? Colors.orange[50] : Colors.blue[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("TABLE: ${data['tableName']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(timeStr, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(data['items'] as List).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text("• ${item['name']} x ${item['quantity']}", style: const TextStyle(fontSize: 14)),
                )),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text("By: ${data['waiterName']}", style: TextStyle(color: Colors.grey[600], fontSize: 11, fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        String nextStatus = status;
                        if (status == 'Pending') nextStatus = 'Preparing';
                        else if (status == 'Preparing') nextStatus = 'Done';
                        else if (status == 'Done') nextStatus = 'Served';
                        
                        if (nextStatus != status) {
                          FirebaseFirestore.instance.collection('kots').doc(id).update({'status': nextStatus});
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status == 'Pending' ? Colors.blue : (status == 'Preparing' ? Colors.orange : Colors.green),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }




  void _showManagementMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text("CASHIER MANAGEMENT", style: TextStyle(fontWeight: FontWeight.bold))),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.fastfood, color: Colors.blue),
            title: const Text("Add New Menu Item"),
            onTap: () {
              Navigator.pop(context);
              // I'll link to the Admin Menu Tab logic or a simple form
              _showAddMenuItemDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_bar, color: Colors.orange),
            title: const Text("Create Temporary Table"),
            enabled: !_hasCreatedTempTable,
            onTap: () {
              Navigator.pop(context);
              _showAddTableDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: Colors.green),
            title: const Text("Order Oversight (History)"),
            onTap: () {
              Navigator.pop(context);
              _showOrderOversightDialog();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showAddMenuItemDialog() {
     // Simplifying for Cashier: Minimal fields
     final nameCtrl = TextEditingController();
     final priceCtrl = TextEditingController();
     String? selectedCategory;

     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text("New Menu Item"),
         content: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Item Name")),
             TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: "Price"), keyboardType: TextInputType.number),
             FutureBuilder<QuerySnapshot>(
               future: _firestore.collection('menu_categories')
                   .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
                   .get(),
               builder: (context, snap) {
                 if (!snap.hasData) return const SizedBox();
                 return DropdownButtonFormField<String>(
                   hint: const Text("Select Category"),
                   items: snap.data!.docs.map((d) => DropdownMenuItem(value: d['name'].toString(), child: Text(d['name']))).toList(),
                   onChanged: (v) => selectedCategory = v,
                 );
               },
             ),
           ],
         ),
         actions: [
           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
           ElevatedButton(
             onPressed: () async {
               if (nameCtrl.text.isNotEmpty && priceCtrl.text.isNotEmpty && selectedCategory != null) {
                  await _firestore.collection('menu_items').add({
                    'name': nameCtrl.text.trim(),
                    'price': double.tryParse(priceCtrl.text) ?? 0.0,
                    'category': selectedCategory,
                    'isAvailable': true,
                    'restaurantId': context.read<AuthService>().restaurantId,
                  });
                  if (mounted) Navigator.pop(context);
               }
             }, 
             child: const Text("Save")
           ),
         ],
       ),
     );
  }

  void _showAddTableDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Temp Table"),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Table Number/Name")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                 await _firestore.collection('tables').add({
                   'name': nameCtrl.text.trim(),
                   'capacity': 4,
                   'section': 'Temporary',
                   'status': 'available',
                   'restaurantId': context.read<AuthService>().restaurantId,
                 });
                 setState(() => _hasCreatedTempTable = true);
                 if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }



  void _reprintBill(String orderId, Map<String, dynamic> data) {
    String billNo = orderId.substring(0, 6).toUpperCase();
    if (data.containsKey('receiptNumber')) {
      billNo = data['receiptNumber'].toString().padLeft(6, '0');
      data['receiptNumber'] = data['receiptNumber']; // Ensure it's available in data for the template if needed
    }

    ReportService.printFinalBill(
      orderData: data,
      orderId: billNo,
      subtotal: (data['subtotal'] ?? 0.0).toDouble(),
      cgst: (data['cgst'] ?? 0.0).toDouble(),
      sgst: (data['sgst'] ?? 0.0).toDouble(),
      total: (data['grandTotal'] ?? 0.0).toDouble(),
      paymentMode: data['paymentMode'] ?? 'Cash',
    );
  }

  void _showNewOrderDialog() {
     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text("Start New Order"),
         content: const Text("To place a new order, please select an available (green) table from the dashboard grid."),
         actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
       ),
     );
  }

  void _showOrderOversightDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history, color: Color(0xFFFCDD22)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Order History", 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.download, color: Color(0xFFFCDD22)),
              tooltip: "Download Today's Order History",
              onPressed: () {
                final auth = context.read<AuthService>();
                _downloadDailyCollection(auth.restaurantId, auth.restaurantName ?? "YUG POS");
              },
            ),
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.close, color: Colors.white54), 
              onPressed: () => Navigator.pop(context)
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 500,
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('orders')
                .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
                .orderBy('createdAt', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              
              final orders = snapshot.data!.docs;
              if (orders.isEmpty) return const Center(child: Text("No recent orders", style: TextStyle(color: Colors.white54)));

              return ListView.separated(
                itemCount: orders.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final doc = orders[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final orderId = doc.id;
                  final status = data['status'] ?? 'unknown';
                  final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final customerName = data['customerName'] ?? 'Walk-in';
                  final paymentMode = data['paymentMode'] ?? ((status == 'completed' || status == 'billed') ? 'Paid' : 'Unpaid');
                  final items = data['items'] as List? ?? [];

                  return ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    collapsedIconColor: Colors.white38,
                    iconColor: const Color(0xFFFCDD22),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['receiptNumber'] != null 
                                  ? "Bill #${data['receiptNumber']}" 
                                  : "Order #${orderId.substring(orderId.length - 6).toUpperCase()}", 
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                              ),
                              Text("$customerName • ${DateFormat('hh:mm a').format(timestamp)}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("₹${data['totalAmount']}", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold, fontSize: 14)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (status == 'completed' || status == 'billed' ? Colors.green : Colors.orange).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                (status == 'completed' || status == 'billed') ? "PAID ($paymentMode)" : status.toUpperCase(),
                                style: TextStyle(color: status == 'completed' || status == 'billed' ? Colors.green : Colors.orange, fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...items.map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("${item['quantity']}x ${item['name']}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  Text("₹${(item['price'] ?? 0) * (item['quantity'] ?? 1)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            )).toList(),
                            const Divider(color: Colors.white10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.print, size: 16),
                                  label: const Text("REPRINT"),
                                  onPressed: () => _printBillForOrder(orderId),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFFCDD22),
                                    side: const BorderSide(color: Color(0xFFFCDD22)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showOrderDetailPanel(TableModel table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: const Color(0xFF141615),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StreamBuilder<DocumentSnapshot>(
            stream: table.currentOrderId != null 
                ? _firestore.collection('orders').doc(table.currentOrderId).snapshots()
                : const Stream.empty(),
            builder: (context, snapshot) {
              if (table.currentOrderId == null) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text("Table is now available", style: TextStyle(color: Colors.grey)),
                ));
              }
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text("Order not found or already cleared"));
              }
              final orderData = snapshot.data!.data() as Map<String, dynamic>;
              final items = orderData['items'] as List;
              final total = orderData['totalAmount'] ?? 0.0;

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("TABLE: ${table.name}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                              Row(
                                children: [
                                  Flexible(child: Text("Customer: ${orderData['customerName'] ?? 'Walk-in'}", style: const TextStyle(fontSize: 14, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text("ADD ITEM"),
                              onPressed: () => _showAddItemDialog(table.currentOrderId!, orderData),
                            ),
                            const SizedBox(width: 8),
                            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _buildOrderItemRow(table.currentOrderId!, orderData, item, index);
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141615),
                      boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 15, offset: const Offset(0, -5))],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("TOTAL AMOUNT", style: TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                            Text("₹${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFFCDD22))),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => _showBillingDialog(table, orderData),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFCDD22),
                            foregroundColor: const Color(0xFF141615),
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 8,
                            shadowColor: const Color(0xFFFCDD22).withOpacity(0.3),
                          ),
                          child: const Text("GENERATE BILL", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.2)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                icon: const Icon(Icons.block, color: Colors.redAccent, size: 18),
                                label: const Text("CANCEL ORDER", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                onPressed: () => _confirmCancelOrder(table, orderData),
                              ),
                            ),
                            Container(width: 1, height: 16, color: Colors.white10),
                            Expanded(
                              child: TextButton.icon(
                                icon: const Icon(Icons.cleaning_services, color: Colors.orangeAccent, size: 18),
                                label: const Text("CLEAR TABLE", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                onPressed: () => _showClearTableDialog(table),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderItemRow(String orderId, Map<String, dynamic> orderData, Map<String, dynamic> item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                Text("₹${item['price']} x ${item['quantity']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Text("₹${(item['price'] * item['quantity']).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFCDD22))),
          const SizedBox(width: 16),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 16),
                onPressed: () => _updateItemQuantity(orderId, orderData, index, -1),
              ),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 16),
                onPressed: () => _updateItemQuantity(orderId, orderData, index, 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateItemQuantity(String orderId, Map<String, dynamic> orderData, int index, int change) async {
    final items = List<Map<String, dynamic>>.from(orderData['items']);
    final item = Map<String, dynamic>.from(items[index]);
    
    int newQty = (item['quantity'] ?? 0) + change;
    if (newQty <= 0) {
      items.removeAt(index);
    } else {
      item['quantity'] = newQty;
      items[index] = item;
    }

    double newTotal = items.fold(0, (sum, i) => sum + (i['price'] * i['quantity']));
    
    await _firestore.collection('orders').doc(orderId).update({
      'items': items,
      'totalAmount': newTotal,
    });

    if (change > 0) {
      // Logic from 4.3.2: "Any modification auto-generates a new KOT for the added items"
      final restaurantId = context.read<AuthService>().restaurantId;
      final restaurantName = context.read<AuthService>().restaurantName ?? "LDMA POS";
      
      final kotData = {
        'tableName': orderData['tableName'],
        'items': [{
          'name': item['name'],
          'quantity': change,
          'price': item['price'],
        }],
      };
      try {
        await ReportService.printKOTReceipt(kotData, orderId);
      } catch (e) {
        debugPrint("KOT Print Error: $e");
      }

      await _firestore.collection('kots').add({
        'tableId': orderData['tableId'],
        'tableName': orderData['tableName'],
        'orderId': orderId,
        'restaurantId': restaurantId,
        'items': [{
          'name': item['name'],
          'quantity': change,
        }],
        'waiterName': 'Cashier Overlay',
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _confirmCancelOrder(TableModel table, Map<String, dynamic> orderData) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Order?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Please specify a reason for cancellation:"),
            TextField(controller: reasonController, decoration: const InputDecoration(hintText: "Reason")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reason is required")));
                return;
              }
              
              final batch = _firestore.batch();
              final orderRef = _firestore.collection('orders').doc(table.currentOrderId);
              final tableRef = _firestore.collection('tables').doc(table.id);

              batch.update(orderRef, {
                'status': 'cancelled',
                'cancelReason': reasonController.text.trim(),
                'cancelledAt': FieldValue.serverTimestamp(),
              });

              batch.update(tableRef, {
                'status': 'available',
                'currentOrderId': null,
              });

              if (table.currentOrderId != null) {
                final kotsSnap = await _firestore.collection('kots').where('orderId', isEqualTo: table.currentOrderId).get();
                for (var doc in kotsSnap.docs) {
                  batch.delete(doc.reference);
                }
              }

              await batch.commit();

              if (mounted) {
                Navigator.pop(context); // Dialog
                Navigator.pop(context); // Panel
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order cancelled and table cleared.")));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("CONFIRM CANCEL"),
          ),
        ],
      ),
    );
  }

  void _showClearTableDialog(TableModel table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
        title: Text("Clear Table ${table.name}?", style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Choose how you'd like to clear this table:", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            if (table.currentOrderId != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text("Note: This table has an active order.", style: TextStyle(color: Colors.blue, fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => safePop(context), child: const Text("CANCEL")),
          // Option 1: JUST CLEAR (For mistakes/tests)
          OutlinedButton(
            onPressed: () async {
              if (_isNavigating) return;
              setState(() => _isNavigating = true);
              safePop(context);
              await _performTableClear(table, settleAndPrint: false);
              setState(() => _isNavigating = false);
            },
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
            child: const Text("CLEAR ONLY", style: TextStyle(color: Colors.red)),
          ),
          // Option 2: SETTLE & PRINT (Standard workflow)
          if (table.currentOrderId != null)
            ElevatedButton(
              onPressed: () async {
                if (_isNavigating) return;
                setState(() => _isNavigating = true);
                safePop(context);
                
                final orderSnap = await _firestore.collection('orders').doc(table.currentOrderId).get();
                if (orderSnap.exists) {
                  final orderData = orderSnap.data() as Map<String, dynamic>;
                  _showBillingDialog(table, orderData);
                } else {
                  await _performTableClear(table, settleAndPrint: false);
                }
                setState(() => _isNavigating = false);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFCDD22), foregroundColor: Colors.black),
              child: const Text("FINISH & BILL"),
            ),
        ],
      ),
    );
  }

  Future<void> _performTableClear(TableModel table, {required bool settleAndPrint}) async {
    try {
      final String? orderId = table.currentOrderId;
      
      if (!settleAndPrint) {
        // Just delete the order and free table
        if (orderId != null) {
          await _firestore.collection('orders').doc(orderId).delete();
        }
      }

      await _firestore.collection('tables').doc(table.id).update({
        'status': 'available',
        'currentOrderId': null,
      });

      if (mounted) {
        setState(() {
          if (_selectedTableId == table.id) {
            _selectedTableId = null;
            _selectedOrderData = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Table cleared successfully.")));
      }
    } catch (e) {
      debugPrint("Clear Table Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error clearing table: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showBillingDialog(TableModel table, Map<String, dynamic> orderData) {
    String selectedPaymentMode = 'Cash';
    final subtotal = (orderData['totalAmount'] ?? 0.0).toDouble();
    final cgst = 0.0;
    final sgst = 0.0;
    final grandTotal = subtotal;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Generate Final Bill"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBillSummaryRow("Total Amount", subtotal, isBold: true),
              const Divider(),
              const SizedBox(height: 24),
              const Text("Payment Mode:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Cash', 'Card', 'UPI'].map((mode) => ChoiceChip(
                  label: Text(mode),
                  selected: selectedPaymentMode == mode,
                  onSelected: (selected) {
                    if (selected) setDialogState(() => selectedPaymentMode = mode);
                  },
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ElevatedButton(
              onPressed: () => _processBilling(table, orderData, subtotal, cgst, sgst, grandTotal, selectedPaymentMode),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text("CONFIRM & PRINT"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillSummaryRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 18 : 14)),
          Text("₹${amount.toStringAsFixed(2)}", style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 18 : 14)),
        ],
      ),
    );
  }

  /// Windows-safe receipt counter bump (no Firestore `runTransaction`).
  ///
  /// Note: This is not atomic vs concurrent cashiers; it is intended as a
  /// stability workaround for the Windows platform-threading issue.
  Future<int> _nextReceiptNoNonTxn(String restaurantId) async {
    final counterRef = _firestore.collection('receipt_counters').doc(restaurantId);
    final counterDoc = await counterRef.get();
    final raw = counterDoc.data()?['lastReceiptNo'];
    final last = raw is int
        ? raw
        : raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '') ?? 0;
    final next = last + 1;
    await counterRef.set({'lastReceiptNo': next}, SetOptions(merge: true));
    return next;
  }

  Future<void> _processBilling(TableModel table, Map<String, dynamic> orderData, double subtotal, double cgst, double sgst, double total, String paymentMode) async {
    try {
      final auth = context.read<AuthService>();
      final restaurantId = auth.restaurantId;
      final restaurantName = auth.restaurantName ?? "YUG POS";
      
      if (restaurantId == null) throw "Unauthorized: Restaurant ID not found.";

      final orderRef = _firestore.collection('orders').doc(table.currentOrderId);
      final tableRef = _firestore.collection('tables').doc(table.id);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final collectionRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");
      final counterRef = _firestore.collection('receipt_counters').doc(restaurantId);

      // Pre-fetch KOTs
      final kotsSnap = await _firestore.collection('kots').where('orderId', isEqualTo: table.currentOrderId).get();

      int assignedReceiptNo = 0;
      // Revenue logic (computed once for both branches)
      final orderTypeStr = (orderData['orderType'] as String?)?.toLowerCase() ?? '';
      final orderSource = (orderData['orderSource'] as String?)?.toLowerCase() ?? '';

      final bool isTakeaway = orderTypeStr == 'takeaway' || orderData['tableName'] == 'Takeaway';
      final bool isDelivery = orderTypeStr == 'delivery' || orderSource == 'delivery';
      final bool isOnline = orderTypeStr == 'online' || orderSource == 'zomato' || orderSource == 'swiggy';

      final updates = <String, dynamic>{
        'netCollection': FieldValue.increment(total),
        'grossCollection': FieldValue.increment(subtotal),
        'billCount': FieldValue.increment(1),
        'restaurantId': restaurantId,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (isOnline) {
        updates['onlineCollection'] = FieldValue.increment(total);
        updates['onlineCount'] = FieldValue.increment(1);
      } else if (isTakeaway) {
        updates['takeawayCollection'] = FieldValue.increment(total);
        updates['takeawayCount'] = FieldValue.increment(1);
      } else if (isDelivery) {
        updates['deliveryCollection'] = FieldValue.increment(total);
        updates['deliveryCount'] = FieldValue.increment(1);
      } else {
        updates['tableCollection'] = FieldValue.increment(total);
        updates['tableCount'] = FieldValue.increment(1);
      }

      if (Platform.isWindows) {
        // Windows workaround: avoid Firestore `runTransaction` due to
        // `firebase_firestore/transaction/...` non-platform thread crashes.
        assignedReceiptNo = await _nextReceiptNoNonTxn(restaurantId);

        final batch = _firestore.batch();
        batch.update(orderRef, {
          'status': 'billed',
          'subtotal': subtotal,
          'cgst': cgst,
          'sgst': sgst,
          'grandTotal': total,
          'paymentMode': paymentMode,
          'receiptNumber': assignedReceiptNo,
          'billedAt': FieldValue.serverTimestamp(),
        });

        batch.update(tableRef, {
          'status': 'available',
          'currentOrderId': null,
        });

        batch.set(collectionRef, updates, SetOptions(merge: true));

        for (var doc in kotsSnap.docs) {
          batch.update(doc.reference, {'status': 'Served'});
        }

        await batch.commit();
      } else {
        await _firestore.runTransaction((transaction) async {
          final counterSnap = await transaction.get(counterRef);
          assignedReceiptNo = counterSnap.exists ? (counterSnap.data()!['lastReceiptNo'] ?? 0) + 1 : 1;

          transaction.update(orderRef, {
            'status': 'billed',
            'subtotal': subtotal,
            'cgst': cgst,
            'sgst': sgst,
            'grandTotal': total,
            'paymentMode': paymentMode,
            'receiptNumber': assignedReceiptNo,
            'billedAt': FieldValue.serverTimestamp(),
          });

          transaction.update(tableRef, {
            'status': 'available',
            'currentOrderId': null,
          });

          transaction.set(collectionRef, updates, SetOptions(merge: true));
          transaction.set(counterRef, {'lastReceiptNo': assignedReceiptNo}, SetOptions(merge: true));

          for (var doc in kotsSnap.docs) {
            transaction.update(doc.reference, {'status': 'Served'});
          }
        });
      }

      final strReceiptNo = assignedReceiptNo.toString().padLeft(6, '0');
      orderData['receiptNumber'] = assignedReceiptNo;

      try {
        await ReportService.printFinalBill(
          orderData: orderData,
          orderId: strReceiptNo,
          subtotal: subtotal,
          cgst: cgst,
          sgst: sgst,
          total: total,
          paymentMode: paymentMode,
          hotelName: restaurantName,
        );
      } catch (e) {
        debugPrint("Final Bill Printing failed: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error printing bill: $e"), backgroundColor: Colors.orange));
        }
      }

      if (mounted) {
        safePop(context); // Dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Billing #$strReceiptNo successfully recorded!"), backgroundColor: Colors.blue));
        setState(() {
          _selectedTableId = null;
          _selectedOrderData = null;
          _isNavigating = false;
        });
      }
    } catch (e) {
      debugPrint("Process Billing Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }
  void _showAddItemDialog(String orderId, Map<String, dynamic> orderData) {
    String searchQuery = '';
    final searchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Add Item to Order"),
          content: SizedBox(
            width: 500,
            height: 600,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              setDialogState(() => searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (value) => setDialogState(() => searchQuery = value.toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<QuerySnapshot>(
                    future: _firestore.collection('menu_items')
                        .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
                        .get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      
                      final allItems = snapshot.data!.docs.where((doc) {
                        return (doc.data() as Map<String, dynamic>)['isAvailable'] == true;
                      }).toList();

                      // Filter by search
                      final items = searchQuery.isEmpty
                          ? allItems
                          : allItems.where((doc) {
                              final name = (doc.data() as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
                              return name.contains(searchQuery);
                            }).toList();

                      if (items.isEmpty) return const Center(child: Text("No items found", style: TextStyle(color: Colors.grey)));

                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final data = item.data() as Map<String, dynamic>;
                          return ListTile(
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.fastfood, color: Colors.orange[400], size: 22),
                            ),
                            title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text("₹${data['price']}"),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                              onPressed: () async {
                                final currentItems = List<Map<String, dynamic>>.from(orderData['items']);
                                final newItem = {
                                  'name': data['name'],
                                  'price': (data['price'] as num).toDouble(),
                                  'quantity': 1,
                                };

                                int existingIdx = currentItems.indexWhere((i) => i['name'] == data['name']);
                                if (existingIdx != -1) {
                                  currentItems[existingIdx]['quantity'] += 1;
                                } else {
                                  currentItems.add(newItem);
                                }

                                double newTotal = currentItems.fold(0, (sum, i) => sum + ((i['price'] as num) * (i['quantity'] as num)));

                                await _firestore.collection('orders').doc(orderId).update({
                                  'items': currentItems,
                                  'totalAmount': newTotal,
                                });

                                final auth = context.read<AuthService>();
                                final kotData = {
                                  'tableName': orderData['tableName'],
                                  'items': [{'name': data['name'], 'quantity': 1, 'price': (data['price'] as num).toDouble()}],
                                };
                                await ReportService.printKOTReceipt(kotData, orderId);

                                await _firestore.collection('kots').add({
                                  'tableId': orderData['tableId'],
                                  'tableName': orderData['tableName'],
                                  'orderId': orderId,
                                  'restaurantId': auth.restaurantId,
                                  'items': [{'name': data['name'], 'quantity': 1}],
                                  'waiterName': 'Cashier',
                                  'status': 'Pending',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });

                                if (mounted) Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added ${data['name']}")));
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => safePop(context), child: const Text("Close"))],
        ),
      ),
    );
  }



  Widget _buildTableZone(String? restaurantId) {
    if (restaurantId == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)));
    }
    return Container(
      color: const Color(0xFF141615),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TABLES", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1)),
                IconButton(
                  icon: const Icon(Icons.add, color: Color(0xFFFCDD22), size: 20),
                  onPressed: _showAddTableDialog,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // 1. Order Type Switcher (from screenshot)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF141615),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  _buildOrderTypeToggle('Dine In', Icons.check, true), 
                  _buildOrderTypeToggle('Takeaway', Icons.shopping_bag, false),
                  _buildOrderTypeToggle('Delivery', Icons.delivery_dining, false),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<QuerySnapshot>(
              future: _firestore.collection('tables')
                  .where('restaurantId', isEqualTo: restaurantId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red, fontSize: 10)));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final tables = snapshot.data!.docs.map((doc) => TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
                
                // Extract unique sections (Floors)
                final floorSections = tables.map((t) => t.section.trim()).toSet().toList();
                floorSections.sort();

                // Auto-select first section if none selected
                if (_selectedTableSection == null && floorSections.isNotEmpty) {
                  // We use a post frame callback to avoid setState during build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedTableSection == null) {
                      setState(() => _selectedTableSection = floorSections.first);
                    }
                  });
                }

                final displayTables = _selectedTableSection == null 
                  ? tables 
                  : tables.where((t) => t.section.trim() == _selectedTableSection).toList();

                return Column(
                  children: [
                    // Section (Floor) Selector
                    if (floorSections.isNotEmpty)
                      Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: floorSections.length,
                          itemBuilder: (context, index) {
                            final section = floorSections[index];
                            final isSelected = _selectedTableSection == section;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0, top: 4, bottom: 4),
                              child: ChoiceChip(
                                label: Text(section.toUpperCase(), 
                                  style: TextStyle(color: isSelected ? const Color(0xFF141615) : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                selected: isSelected,
                                selectedColor: const Color(0xFFFCDD22),
                                backgroundColor: const Color(0xFF2A2A2A),
                                onSelected: (val) => setState(() => _selectedTableSection = section),
                              ),
                            );
                          },
                        ),
                      ),
                    const Divider(color: Colors.white10),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          const SizedBox(height: 8),
                          _buildSubGrid(displayTables),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  void _promptClearTable(TableModel table) {
     _showClearTableDialog(table);
  }
  
  void _startQuickOrder({String? type}) {
    setState(() {
      // Generate a pseudo short ID for the quick order
      final shortId = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      _selectedTableId = 'QO-$shortId';
      if (type != null) _selectedOrderType = type;
      _selectedOrderData = null;
      _hasCreatedTempTable = true;
    });
  }

  Widget _buildItemsZone(String? restaurantId) {
    if (restaurantId == null || _isMenuLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)));
    }

    return Column(
      children: [
        // Mobile Search Bar
        if (MediaQuery.of(context).size.width < 600)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            color: const Color(0xFF141615),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF141615),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: TextField(
                controller: _itemSearchController,
                onChanged: (v) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: "Search menu items...",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: Colors.grey, size: 16),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
        _buildCategoryScroll(restaurantId),
        Expanded(child: _buildItemsGrid(restaurantId)),
      ],
    );
  }

  Future<void> _fetchMenuData(String? restaurantId, {bool force = false}) async {
    if (restaurantId == null || (_isMenuLoading && !force)) return;
    
    if (force) {
      _cachedItems = null;
      _cachedCategories = null;
    }
    
    setState(() => _isMenuLoading = true);
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
      setState(() => _isMenuLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading menu: $e")));
      }
    }
  }

  Widget _buildCategoryScroll(String? restaurantId) {
    final categories = _cachedCategories ?? [];
    
    return Container(
      height: 50,
      color: const Color(0xFF141615),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCategoryChip("All", _selectedCategory == null);
          }
          final cat = categories[index - 1];
          return _buildCategoryChip(cat, _selectedCategory == cat);
        },
      ),
    );
  }

  Widget _buildCategoryChip(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: isSelected ? const Color(0xFF141615) : Colors.white70)),
        selected: isSelected,
        selectedColor: const Color(0xFFFCDD22),
        backgroundColor: const Color(0xFF2A2A2A),
        onSelected: (selected) {
          setState(() {
            _selectedCategory = label == "All" ? null : label;
          });
        },
      ),
    );
  }

  Widget _buildItemsGrid(String? restaurantId) {
    final items = _cachedItems ?? [];
    final filteredItems = items.where((item) {
      final matchesSearch = item.name.toLowerCase().contains(_itemSearchController.text.toLowerCase());
      final matchesCategory = _selectedCategory == null || item.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return filteredItems.isEmpty
      ? const Center(child: Text("No items found", style: TextStyle(color: Colors.grey)))
      : GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: filteredItems.length,
          itemBuilder: (context, index) {
            final item = filteredItems[index];
            final isMobile = MediaQuery.of(context).size.width < 600;

            int orderQuantity = 0;
            if (isMobile) {
              final cart = context.watch<CartProvider>();
              final existingIdx = cart.items.indexWhere((i) => i.item.id == item.id);
              if (existingIdx != -1) orderQuantity = cart.items[existingIdx].quantity;
            } else if (_selectedOrderData != null) {
              final cartItems = _selectedOrderData!['items'] as List<dynamic>? ?? [];
              final existing = cartItems.firstWhere((i) => i['name'] == item.name, orElse: () => null);
              if (existing != null) orderQuantity = (existing['quantity'] as num?)?.toInt() ?? 0;
            }

            return GestureDetector(
              onTap: () => _handleAddItemToSelectedTable(item),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF141615),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: orderQuantity > 0 ? const Color(0xFFFCDD22) : Colors.white12, width: orderQuantity > 0 ? 2 : 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: item.imageUrl != null 
                              ? Image.network(item.imageUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.white24, size: 40))
                              : const Icon(Icons.fastfood, color: Colors.white24, size: 40),
                          ),
                          if (orderQuantity > 0)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFCDD22),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  orderQuantity.toString(),
                                  style: const TextStyle(
                                    color: const Color(0xFF141615),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text("₹${item.price.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }

  void _handleAddItemToSelectedTable(MenuItem item) async {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      context.read<CartProvider>().addItem(item);
      return;
    }

    if (_selectedTableId == null) {
      if (_selectedOrderType == 'Takeaway' || _selectedOrderType == 'Delivery') {
        _startQuickOrder(type: _selectedOrderType);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a table first for Dine In orders!")));
        return;
      }
    }
    
    // Logic to add to existing order or create new one
    if (_selectedOrderData == null) {
      // Create new order
      final auth = context.read<AuthService>();
      String tableName = 'Takeaway/Del';
      if (!_hasCreatedTempTable) {
        final tableDoc = await _firestore.collection('tables').doc(_selectedTableId).get();
        tableName = tableDoc['name'];
      }

      final newOrderRef = await _firestore.collection('orders').add({
        'tableId': _selectedTableId,
        'tableName': tableName,
        'restaurantId': auth.restaurantId,
        'items': [{'name': item.name, 'price': item.price, 'quantity': 1}],
        'totalAmount': item.price,
        'status': 'pending',
        'orderSource': _selectedOrderType.toLowerCase().replaceAll(' ', '_'),
        'orderType': _selectedOrderType.toLowerCase(),
        'takeawayStatus': _selectedOrderType.toLowerCase() == 'takeaway' ? 'pending' : null,
        'deliveryStatus': _selectedOrderType.toLowerCase() == 'delivery' ? 'pending' : null,
        'isDelivered': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!_hasCreatedTempTable) {
        await _firestore.collection('tables').doc(_selectedTableId).update({
          'status': 'occupied',
          'currentOrderId': newOrderRef.id,
        });
      }

      // Send initial KOT
      await _firestore.collection('kots').add({
        'tableId': _selectedTableId,
        'tableName': tableName,
        'orderId': newOrderRef.id,
        'restaurantId': auth.restaurantId,
        'items': [{'name': item.name, 'quantity': 1}],
        'waiterName': 'Cashier',
        'status': 'Pending',
        'orderType': _selectedOrderType.toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      final newDoc = await newOrderRef.get();
      setState(() {
        _selectedOrderData = newDoc.data() as Map<String, dynamic>;
        _selectedOrderData!['id'] = newDoc.id;
      });
    } else {
      // Update existing order
      final orderId = _selectedOrderData!['id'];
      List items = List.from(_selectedOrderData!['items']);
      int existingIdx = items.indexWhere((i) => i['name'] == item.name);
      
      if (existingIdx != -1) {
        items[existingIdx]['quantity'] += 1;
      } else {
        items.add({'name': item.name, 'price': item.price, 'quantity': 1});
      }

      double newTotal = items.fold(0, (sum, i) => sum + (i['price'] * i['quantity']));

      await _firestore.collection('orders').doc(orderId).update({
        'items': items,
        'totalAmount': newTotal,
      });

      setState(() {
        _selectedOrderData!['items'] = items;
        _selectedOrderData!['totalAmount'] = newTotal;
      });

      // Send incremental KOT
      await _firestore.collection('kots').add({
        'tableId': _selectedTableId,
        'tableName': _selectedOrderData!['tableName'],
        'orderId': orderId,
        'restaurantId': context.read<AuthService>().restaurantId,
        'items': [{'name': item.name, 'quantity': 1}],
        'waiterName': 'Cashier',
        'status': 'Pending',
        'orderType': _selectedOrderType.toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _selectedOrderData!['items'] = items;
        _selectedOrderData!['totalAmount'] = newTotal;
      });
    }
  }

  void _increaseItemQuantity(String itemName) {
    if (_selectedOrderData == null) return;
    List items = List.from(_selectedOrderData!['items']);
    int idx = items.indexWhere((i) => i['name'] == itemName);
    if (idx != -1) {
      items[idx]['quantity'] += 1;
      _updateOrderItems(items);
    }
  }

  void _decreaseItemQuantity(String itemName) {
    if (_selectedOrderData == null) return;
    List items = List.from(_selectedOrderData!['items']);
    int idx = items.indexWhere((i) => i['name'] == itemName);
    if (idx != -1) {
      if (items[idx]['quantity'] > 1) {
        items[idx]['quantity'] -= 1;
      } else {
        items.removeAt(idx);
      }
      _updateOrderItems(items);
    }
  }

  void _updateOrderItems(List items) async {
    double newTotal = items.fold(0, (sum, i) => sum + (i['price'] * i['quantity']));
    final orderId = _selectedOrderData!['id'];
    
    setState(() {
      _selectedOrderData!['items'] = items;
      _selectedOrderData!['totalAmount'] = newTotal;
    });

    if (!_hasCreatedTempTable) {
      await _firestore.collection('orders').doc(orderId).update({
        'items': items,
        'totalAmount': newTotal,
      });
    }
  }

  Widget _buildMobileCartTab(String? restaurantId) {
    return Column(
      children: [
        // 1. Order Type Chips
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(child: _buildMobileSegment('Dine In', Icons.restaurant)),
              const SizedBox(width: 8),
              Expanded(child: _buildMobileSegment('Takeaway', Icons.shopping_bag)),
              const SizedBox(width: 8),
              Expanded(child: _buildMobileSegment('Delivery', Icons.delivery_dining)),
            ],
          ),
        ),
        // 2. Collection Chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: _buildCollectionCounter(restaurantId),
        ),
        const Divider(color: Colors.white12),
        // 3. Cart Content
        Expanded(
          child: _selectedTableId == null
            ? Center(
                child: Text("Add items to start order", style: TextStyle(color: Colors.grey[600])),
              )
            : Column(
                children: [
                  // Order Header
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("ORDER #${_selectedTableId!.substring(0, 4).toUpperCase()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            if (_selectedOrderData != null)
                              Row(
                                children: [
                                  Text("Customer: ${_selectedOrderData!['customerName'] ?? 'Walk-in'}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  const SizedBox(width: 8),
                                  if (_selectedOrderData!['status'] == 'completed' || _selectedOrderData!['status'] == 'billed')
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.green.withOpacity(0.5)),
                                      ),
                                      child: Text(
                                        "COMPLETED (${_selectedOrderData!['paymentMode'] ?? ''})",
                                        style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _confirmClearTableById(_selectedTableId!),
                          icon: const Icon(Icons.close, size: 16, color: Colors.white),
                          label: const Text("CLEAR", style: TextStyle(color: Colors.white)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white30),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Items List
                  Expanded(
                    child: _selectedOrderData == null || (_selectedOrderData!['items'] as List).isEmpty
                      ? const Center(child: Text("Cart is empty", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: (_selectedOrderData!['items'] as List).length,
                          itemBuilder: (context, index) {
                            final item = _selectedOrderData!['items'][index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141615),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Text("₹${item['price']} × ${item['quantity']}", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  // +/- Controls
                                  Row(
                                    children: [
                                      _buildQtyBtn(Icons.remove, () => _decreaseItemQuantity(item['name'])),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text("${item['quantity']}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                                      ),
                                      _buildQtyBtn(Icons.add, () => _increaseItemQuantity(item['name'])),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 50,
                                    child: Text("₹${(item['price'] * item['quantity']).toStringAsFixed(0)}", 
                                      style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.right),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                  ),
                  // Bottom Actions - only show when order data is loaded
                  if (_selectedOrderData != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1C1C1C),
                      border: Border(top: BorderSide(color: Colors.white12)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Total Payable", style: TextStyle(color: Colors.grey, fontSize: 14)),
                            Text("₹${(_selectedOrderData!['totalAmount'] ?? 0).toStringAsFixed(0)}", 
                              style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildActionBtn("KOT", () => _printKOTForOrder(_selectedOrderData!['id']))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildActionBtn(_selectedOrderData!['status'] == 'completed' || _selectedOrderData!['status'] == 'billed' ? "CLEAR TABLE" : "SETTLE", () => _settleOrder(_selectedOrderData!['id']))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        ),
      ],
    );
  }

  Widget _buildMobileSegment(String label, IconData icon) {
    final isSelected = _selectedOrderType == label;
    return GestureDetector(
        onTap: () {
        if (label == 'Takeaway') {
          showDialog(context: context, builder: (_) => TakeawayOrderDialog(orderType: 'takeaway'));
        } else if (label == 'Delivery') {
          showDialog(context: context, builder: (_) => TakeawayOrderDialog(orderType: 'delivery'));
        } else {
          setState(() {
            _selectedOrderType = label;
            _mobileTabIndex = 0; // Ensure menu tab is active
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFCDD22).withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: isSelected ? const Color(0xFFFCDD22) : Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? const Color(0xFFFCDD22) : Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isSelected ? const Color(0xFFFCDD22) : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  void _handleTableSelect(TableModel table) async {
    final isMobile = MediaQuery.of(context).size.width < 1000;
    if (!isMobile) {
      final cart = context.read<CartProvider>();
      cart.setOrderType(OrderType.dineIn);
      cart.setTable(table.id, table.name);
    }

    if (table.status != TableStatus.available && table.currentOrderId != null) {
      try {
        final doc = await _firestore.collection('orders').doc(table.currentOrderId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _selectedOrderData = data;
            _selectedOrderData!['id'] = doc.id;
            _selectedTableId = table.id;
          });
        
          // Sync CartProvider for mobile view
          final cart = context.read<CartProvider>();
          cart.setOrderType(OrderType.dineIn);
          cart.setTable(table.id, table.name);
          cart.setCustomerName(data['customerName'] ?? "Walk-in");
        
          final items = data['items'] as List<dynamic>? ?? [];
          for (var itemData in items) {
            final menuItemIdx = _cachedItems?.indexWhere((i) => i.name == itemData['name']) ?? -1;
            if (menuItemIdx >= 0) {
               cart.addItem(_cachedItems![menuItemIdx], quantity: itemData['quantity'] ?? 1);
            }
          }
          setState(() {
            _mobileTabIndex = 0; // Switch to Menu for mobile/tablet
          });
        }
      } catch (e) {
        // Security rules denial should not hard-crash the UI.
        debugPrint('Table select failed (order read): $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Access denied for this order. Ask admin if needed.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else {
      // Instant start order
      final cart = context.read<CartProvider>();
      cart.clearCart();
      cart.setOrderType(OrderType.dineIn);
      cart.setTable(table.id, table.name);
      cart.setCustomerName("Walk-in");
      setState(() {
        _selectedTableId = table.id;
        _selectedOrderData = null;
        _mobileTabIndex = 0; // Switch to Menu for mobile/tablet
      });
    }
  }



  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey[800]!), borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, color: Colors.white70, size: 14),
      ),
    );
  }

  Widget _buildActionBtn(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildCartBillingZone(String? restaurantId) {
    return Column(
      children: [
        // ── ORDER TYPE ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: const Color(0xFF1C1C1C),
          child: Row(
            children: [
              _buildOrderTypeChip('Dine In',  Icons.restaurant),
              const SizedBox(width: 6),
              _buildOrderTypeChip('Takeaway', Icons.shopping_bag_outlined),
              const SizedBox(width: 6),
              _buildOrderTypeChip('Delivery', Icons.delivery_dining),
            ],
          ),
        ),
        
        if (_selectedTableId == null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedOrderType == 'Dine In' ? Icons.table_bar_outlined : Icons.shopping_cart_outlined, 
                    color: Colors.white10, 
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedOrderType == 'Dine In' 
                      ? "Select a table to start billing"
                      : "Add items to start $_selectedOrderType order",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF141615),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_cart, color: Color(0xFFFCDD22)),
                    const SizedBox(width: 12),
                    Text("ORDER #${_selectedTableId!.substring(0, 4).toUpperCase()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCDD22).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFCDD22).withOpacity(0.5)),
                      ),
                      child: Text(
                        _selectedOrderType.toUpperCase(),
                        style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    _buildUltraCompactButton("CLEAR", Icons.delete, Colors.red, () => _confirmClearTableById(_selectedTableId!)),
                  ],
                ),
                if (_selectedOrderData != null && (_selectedOrderData!['status'] == 'completed' || _selectedOrderData!['status'] == 'billed'))
                   Padding(
                     padding: const EdgeInsets.only(top: 8),
                     child: Row(
                       children: [
                         Container(
                           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                           decoration: BoxDecoration(
                             color: Colors.green.withOpacity(0.15),
                             borderRadius: BorderRadius.circular(6),
                             border: Border.all(color: Colors.green.withOpacity(0.5)),
                           ),
                           child: Row(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               const Icon(Icons.check_circle, color: Colors.green, size: 14),
                               const SizedBox(width: 6),
                               Text(
                                 "BILLED & PAID (${_selectedOrderData!['paymentMode'] ?? ''})",
                                 style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                               ),
                             ],
                           ),
                         ),
                       ],
                     ),
                   ),
              ],
            ),
          ),
          // ── ITEMS LIST ──────────────────────────────────────────
          Expanded(
          child: _selectedOrderData == null 
            ? const Center(child: Text("Cart is empty", style: TextStyle(color: Colors.grey)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: (_selectedOrderData!['items'] as List).length,
                separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05)),
                itemBuilder: (context, index) {
                  final item = _selectedOrderData!['items'][index];
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text("₹${item['price']}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                      // +/- Quantity Controls
                      Row(
                        children: [
                          _buildQtyBtn(Icons.remove, () => _decreaseItemQuantity(item['name'])),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text("${item['quantity']}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                          ),
                          _buildQtyBtn(Icons.add, () => _increaseItemQuantity(item['name'])),
                        ],
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 60,
                        child: Text("₹${(item['price'] * item['quantity']).toStringAsFixed(0)}", 
                          style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right),
                      ),
                    ],
                  );
                },
              ),

        ),
        if (_selectedOrderData != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF141615),
              boxShadow: [BoxShadow(color: const Color(0xFF141615).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Payable", style: TextStyle(color: Colors.grey, fontSize: 16)),
                    Text("₹${(_selectedOrderData!['totalAmount'] ?? 0).toStringAsFixed(0)}", 
                      style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: ElevatedButton(
                        onPressed: () => _printKOTForOrder(_selectedOrderData!['id']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("KOT", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: ElevatedButton(
                        onPressed: () => _settleOrder(_selectedOrderData!['id']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedOrderData!['status'] == 'completed' || _selectedOrderData!['status'] == 'billed' ? Colors.grey[800] : const Color(0xFFFCDD22),
                          foregroundColor: _selectedOrderData!['status'] == 'completed' || _selectedOrderData!['status'] == 'billed' ? Colors.white : const Color(0xFF141615),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          _selectedOrderData!['status'] == 'completed' || _selectedOrderData!['status'] == 'billed' ? "CLEAR TABLE" : "SETTLE", 
                          style: TextStyle(fontWeight: FontWeight.bold, color: _selectedOrderData!['status'] == 'completed' || _selectedOrderData!['status'] == 'billed' ? Colors.white : const Color(0xFF141615))
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ], // Closes if (_selectedOrderData != null)
        ], // Closes else ...[
      ],
    );
  }

  void _confirmClearTableById(String tableId) async {
    final tableDoc = await _firestore.collection('tables').doc(tableId).get();
    if (tableDoc.exists) {
       final table = TableModel.fromMap(tableDoc.id, tableDoc.data() as Map<String, dynamic>);
       _showClearTableDialog(table);
    }
  }

  void _printKOTForOrder(String orderId) async {
    final doc = await _firestore.collection('orders').doc(orderId).get();
    if (doc.exists) {
      final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      data['kotNumber'] = orderId.substring(0, 4).toUpperCase();
      try {
        await ReportService.printKOTReceipt(data, orderId);
      } catch (e) {
        debugPrint("KOT Printing failed: $e");
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("KOT Printed!")));
    }
  }

  void _downloadDailyCollection(String? restaurantId, String restaurantName) async {
    if (restaurantId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Missing Restaurant ID")));
      return;
    }
    
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generating Order History Report... Please wait."), duration: Duration(seconds: 2)));

    try {
      final startOfToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

      // Fetch recent orders, matching the order history dialog's view.
      // We pull the last 50 orders to ensure orders placed late at night or in UTC boundaries aren't incorrectly hidden from daily test downloads.
      final orderSnap = await _firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final ordersList = orderSnap.docs
          .map((doc) {
             final data = doc.data() as Map<String, dynamic>;
             data['id'] = doc.id; // Inject ID for the report
             return data;
          })
          .toList();

      if (ordersList.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No recent orders found."), backgroundColor: Colors.orange));
        return;
      }

      await ReportService.printOrderHistoryReport(
        restaurantName: restaurantName,
        orders: ordersList,
        startDate: ordersList.isNotEmpty 
            ? (ordersList.last['createdAt'] as Timestamp?)?.toDate() ?? startOfToday 
            : startOfToday,
        endDate: DateTime.now(),
      );

      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Report Generation Failed: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _recordRevenueAndUpdateStatus(String orderId, Map<String, dynamic> data, String paymentMode) async {
    if (data['status'] == 'completed' || data['status'] == 'paid') return; // Prevent double counting
    
    final restaurantId = data['restaurantId'];
    final total = (data['totalAmount'] as num).toDouble();
    
    final orderTypeStr = (data['orderType'] as String?)?.toLowerCase() ?? '';
    final orderSource = (data['orderSource'] as String?)?.toLowerCase() ?? '';
    
    bool isTakeaway = orderTypeStr == 'takeaway' || data['tableName'] == 'Takeaway';
    bool isDelivery = orderTypeStr == 'delivery' || orderSource == 'delivery';
    bool isOnline = orderTypeStr == 'online' || orderSource == 'zomato' || orderSource == 'swiggy';

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final collRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");
    
    if (Platform.isWindows) {
      // Windows workaround: avoid Firestore `runTransaction` due to
      // `firebase_firestore/transaction/...` non-platform thread crashes.
      final Map<String, dynamic> updates = {
        'restaurantId': restaurantId,
        'netCollection': FieldValue.increment(total),
        'grossCollection': FieldValue.increment(total),
        'billCount': FieldValue.increment(1),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

      // Payment Mode Breakdown
      if (paymentMode.toLowerCase() == 'upi') {
        updates['upiCollection'] = FieldValue.increment(total);
      } else {
        updates['cashCollection'] = FieldValue.increment(total);
      }
      
      if (isOnline) {
        updates['onlineCollection'] = FieldValue.increment(total);
        updates['onlineCount'] = FieldValue.increment(1);
      } else if (isTakeaway) {
        updates['takeawayCollection'] = FieldValue.increment(total);
        updates['takeawayCount'] = FieldValue.increment(1);
      } else if (isDelivery) {
        updates['deliveryCollection'] = FieldValue.increment(total);
        updates['deliveryCount'] = FieldValue.increment(1);
      } else {
        updates['tableCollection'] = FieldValue.increment(total);
        updates['tableCount'] = FieldValue.increment(1);
      }

      await collRef.set(updates, SetOptions(merge: true));
    } else {
      await _firestore.runTransaction((transaction) async {
        final collDoc = await transaction.get(collRef);
        
        Map<String, dynamic> updates = {
          'netCollection': FieldValue.increment(total),
          'grossCollection': FieldValue.increment(total),
          'billCount': FieldValue.increment(1),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        };

        // Payment Mode Breakdown
        if (paymentMode.toLowerCase() == 'upi') {
          updates['upiCollection'] = FieldValue.increment(total);
        } else {
          updates['cashCollection'] = FieldValue.increment(total);
        }
        
        if (isOnline) {
          updates['onlineCollection'] = FieldValue.increment(total);
          updates['onlineCount'] = FieldValue.increment(1);
        } else if (isTakeaway) {
          updates['takeawayCollection'] = FieldValue.increment(total);
          updates['takeawayCount'] = FieldValue.increment(1);
        } else if (isDelivery) {
          updates['deliveryCollection'] = FieldValue.increment(total);
          updates['deliveryCount'] = FieldValue.increment(1);
        } else {
          updates['tableCollection'] = FieldValue.increment(total);
          updates['tableCount'] = FieldValue.increment(1);
        }

        if (!collDoc.exists) {
          updates['restaurantId'] = restaurantId;
          updates['netCollection'] = total;
          updates['grossCollection'] = total;
          updates['billCount'] = 1;

          // Initialize payment modes
          if (paymentMode.toLowerCase() == 'upi') {
            updates['upiCollection'] = total;
            updates['cashCollection'] = 0.0;
          } else {
            updates['cashCollection'] = total;
            updates['upiCollection'] = 0.0;
          }

          if (isOnline) { updates['onlineCollection'] = total; updates['onlineCount'] = 1; }
          else if (isTakeaway) { updates['takeawayCollection'] = total; updates['takeawayCount'] = 1; }
          else if (isDelivery) { updates['deliveryCollection'] = total; updates['deliveryCount'] = 1; }
          else { updates['tableCollection'] = total; updates['tableCount'] = 1; }
          transaction.set(collRef, updates);
        } else {
          transaction.update(collRef, updates);
        }
      });
    }

    await _firestore.collection('orders').doc(orderId).update({
      'status': 'completed',
      'paymentMode': paymentMode,
      'orderType': _selectedOrderType,
      'billedAt': FieldValue.serverTimestamp(), // standardizing on billedAt
      'completedAt': FieldValue.serverTimestamp(), // keeping for compatibility
    });
    
    if (_selectedOrderData != null && _selectedOrderData!['id'] == orderId) {
       setState(() { 
         _selectedOrderData!['status'] = 'completed'; 
         _selectedOrderData!['paymentMode'] = paymentMode;
       });
    }
  }

  void _printBillForOrder(String orderId, {String? customPaymentMode}) async {
    try {
      final doc = await _firestore.collection('orders').doc(orderId).get();
      if (!doc.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order not found!")));
        return;
      }
      
      final orderData = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      final restaurantId = orderData['restaurantId'];
      if (restaurantId == null) throw "Restaurant ID is missing in order data!";

      // Safe cast: totalAmount can be int, double, or occasionally null
      final rawTotal = orderData['totalAmount'];
      final subtotal = rawTotal is num ? rawTotal.toDouble() : double.tryParse(rawTotal?.toString() ?? '') ?? 0.0;
      const cgst = 0.0;
      const sgst = 0.0;
      final total = subtotal;
      
      final auth = context.read<AuthService>();
      final restaurantName = auth.restaurantName ?? "YUG POS";
      
      int assignedReceiptNo = (orderData['receiptNumber'] as num?)?.toInt() ?? 0;
      
      if (assignedReceiptNo == 0) {
        final counterRef = _firestore.collection('receipt_counters').doc(restaurantId);

        if (Platform.isWindows) {
          // Windows workaround: avoid Firestore `runTransaction`.
          final counterDoc = await counterRef.get();
          final rawLast = counterDoc.data()?['lastReceiptNo'];
          final last = rawLast is int
              ? rawLast
              : rawLast is num
                  ? rawLast.toInt()
                  : int.tryParse(rawLast?.toString() ?? '') ?? 0;
          assignedReceiptNo = last + 1;

          await counterRef.set({'lastReceiptNo': assignedReceiptNo}, SetOptions(merge: true));
          await _firestore.collection('orders').doc(orderId).update({
            'receiptNumber': assignedReceiptNo,
            'status': 'billed',
            'subtotal': subtotal,
            'cgst': cgst,
            'sgst': sgst,
            'grandTotal': total,
            'billedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Run a transaction to get the next receipt number sequentially
          final nextNo = await _firestore.runTransaction<int>((transaction) async {
            final counterDoc = await transaction.get(counterRef);
            int next = 1;
            if (counterDoc.exists) {
              next = ((counterDoc.data()?['lastReceiptNo'] as num?)?.toInt() ?? 0) + 1;
            }
            transaction.set(counterRef, {'lastReceiptNo': next}, SetOptions(merge: true));
            
            // Also update the order during the same transaction
            transaction.update(_firestore.collection('orders').doc(orderId), {
              'receiptNumber': next,
              'status': 'billed',
              'subtotal': subtotal,
              'cgst': cgst,
              'sgst': sgst,
              'grandTotal': total,
              'billedAt': FieldValue.serverTimestamp(),
            });
            
            return next;
          });
          assignedReceiptNo = nextNo;
        }
        orderData['receiptNumber'] = assignedReceiptNo;
      }
      
      final strReceiptNo = assignedReceiptNo.toString().padLeft(6, '0');
      
      final String pMode = customPaymentMode ?? orderData['paymentMode'] as String? ?? "Cash/Unpaid";
      
      final bt = context.read<BluetoothPrinterService>();
      final usb = context.read<UsbPrinterService>();
      final isAndroid = !kIsWeb && Platform.isAndroid;

      // Print the Premium Final Bill
      await ReportService.printFinalBill(
        orderData: orderData,
        orderId: strReceiptNo,
        subtotal: subtotal,
        cgst: cgst,
        sgst: sgst,
        total: total,
        paymentMode: pMode,
        hotelName: restaurantName,
        printerService: isAndroid ? bt : usb,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bill #$strReceiptNo Printed!"), backgroundColor: Colors.blue));
      }
    } catch (e, stack) {
      debugPrint("Billing Error: $e\n$stack");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Billing Failed: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _settleOrder(String orderId) async {
    if (_selectedOrderData == null) return;
    
    _showPaymentSelectionDialog(orderId);
  }

  void _showPaymentSelectionDialog(String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
        title: const Text("Select Payment Method", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("How was the payment made?", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.money, size: 20),
                    label: const Text("CASH"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      safePop(context);
                      _finalizeSettlement(orderId, 'Cash');
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: const Text("UPI"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      safePop(context);
                      _finalizeSettlement(orderId, 'UPI');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _finalizeSettlement(String orderId, String paymentMode) async {
    if (_selectedOrderData == null) return;
    final data = _selectedOrderData!;

    // Case: If already completed, this button acts as 'CLEAR TABLE'
    if (data['status'] == 'completed' || data['status'] == 'billed') {
      if (!_hasCreatedTempTable && _selectedTableId != null) {
        await _firestore.collection('tables').doc(_selectedTableId).update({
          'status': 'available',
          'currentOrderId': null,
        });
      }
      setState(() {
        _selectedOrderData = null;
        _selectedTableId = null;
        _hasCreatedTempTable = false;
      });
      return;
    }

    // Otherwise, Record Revenue and mark as Completed
    await _recordRevenueAndUpdateStatus(orderId, data, paymentMode);

    // Automatically print the final bill with the confirmed payment method
    _printBillForOrder(orderId, customPaymentMode: paymentMode);

    // Update local state to show 'COMPLETED' and keep selection so they can see the change
    setState(() {
      _selectedOrderData!['status'] = 'completed';
      _selectedOrderData!['paymentMode'] = paymentMode;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment recorded via $paymentMode. Order marked as COMPLETED."), 
          backgroundColor: Colors.green
        )
      );
    }
  }

  Widget _buildOrderTypeChip(String type, IconData icon) {
    final isSelected = _selectedOrderType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedOrderType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFCDD22) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFFCDD22) : Colors.white12,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? const Color(0xFF141615) : Colors.white54),
              const SizedBox(height: 2),
              Text(
                type,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? const Color(0xFF141615) : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUltraCompactButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: SizedBox(
        height: 28,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 12),
          label: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
    );
  }

  Widget _buildUltraMiniStatus(TableStatus status) {
    Color color = Colors.red;
    String text = "FREE";
    IconData icon = Icons.circle_outlined;

    switch (status) {
      case TableStatus.available:
        color = Colors.grey;
        text = "FREE";
        icon = Icons.radio_button_unchecked;
        break;
      case TableStatus.occupied:
        color = Colors.red;
        text = "OCC";
        icon = Icons.people;
        break;
      case TableStatus.kotSent:
        color = Colors.orange;
        text = "ONG";
        icon = Icons.restaurant;
        break;
      case TableStatus.billRequested:
        color = Colors.blue;
        text = "BILL";
        icon = Icons.receipt;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: color),
          const SizedBox(width: 2),
          Text(text, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSubGrid(List<TableModel> tables) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final table = tables[index];
        final isSelected = _selectedTableId == table.id;
        final isOccupied = table.status != TableStatus.available;
        
        return GestureDetector(
          onTap: () => _handleTableSelect(table),
          onLongPress: isOccupied ? () => _promptClearTable(table) : null,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141615),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected || isOccupied ? const Color(0xFFFCDD22) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(table.name, 
                  style: TextStyle(
                    color: isSelected || isOccupied ? const Color(0xFFFCDD22) : Colors.white70, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 20
                  )
                ),
                const SizedBox(height: 4),
                Text(table.status == TableStatus.available ? "AVAILABLE" : "OCCUPIED",
                  style: TextStyle(
                    color: isSelected || isOccupied ? const Color(0xFFFCDD22).withOpacity(0.5) : Colors.white24, 
                    fontSize: 10, 
                    fontWeight: FontWeight.w500
                  )
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderTypeToggle(String label, IconData icon, bool defaultSelected) {
    bool isSelected = _selectedOrderType == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          final cart = context.read<CartProvider>();
          if (label == 'Takeaway' || label == 'Delivery') {
             // For Quick Orders, we update state immediately and clear any selected table
             setState(() {
               _selectedOrderType = label;
               _selectedTableId = null;
               _selectedOrderData = null;
               _mobileTabIndex = 0;
             });
             cart.setOrderType(label == 'Takeaway' ? OrderType.takeaway : OrderType.delivery);
             cart.setCustomerName("Takeaway Customer");
          } else {
            setState(() {
              _selectedOrderType = 'Dine In';
              _selectedTableId = null;
              _selectedOrderData = null;
            });
            cart.setOrderType(OrderType.dineIn);
          }
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFCDD22) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? const Color(0xFF141615) : Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label, 
                    style: TextStyle(color: isSelected ? const Color(0xFF141615) : Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    softWrap: false,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildMidnightResetBanner([String? restaurantId]) {
    if (restaurantId == null) return const SizedBox.shrink();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    return FutureBuilder<DocumentSnapshot?>(
      future: _firestore.collection('daily_collections').doc(docId).get()
          .catchError((e) => null),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null || snapshot.data!.exists) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Colors.orange[100],
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 12),
              const Expanded(child: Text("New day detected. Please refresh to start a new collection session.", style: TextStyle(color: const Color(0xFF141615), fontWeight: FontWeight.bold))),
              TextButton(onPressed: () => setState(() {}), child: const Text("REFRESH")),
            ],
          ),
        );
      },
    );
  }
}

