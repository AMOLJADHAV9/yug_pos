import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../models/table_model.dart';
import '../models/menu_item.dart';
import '../providers/cart_provider.dart';
import '../services/report_service.dart';
import '../services/usb_printer_service.dart';
import '../screens/cashier/v2_styles.dart';

class POSViewContent extends StatefulWidget {
  final bool isAdminTab;
  const POSViewContent({super.key, this.isAdminTab = false});

  @override
  State<POSViewContent> createState() => _POSViewContentState();
}

class _POSViewContentState extends State<POSViewContent> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedZone = 'AC-Hall 101';
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  // For History column filters
  String _hTab = 'all'; // all, table, takeaway, delivery
  String _hFilter = 'active'; // active, new, preparing, ready, done
  double _gstPercentage = 0.0;
  String? _restaurantAddress;
  String? _restaurantName;
  String? _gstNumber;
  String? _lastRestaurantId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchRestaurantSettings();
    });
  }

  void _fetchRestaurantSettings() async {
    final auth = context.read<AuthService>();
    final resId = auth.restaurantId;
    if (resId != null) {
      _lastRestaurantId = resId;
      try {
        final doc = await _firestore.collection('restaurants').doc(resId).get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _gstPercentage = (data['gstPercentage'] ?? 0.0).toDouble();
            _restaurantAddress = data['address']?.toString();
            _restaurantName = data['name']?.toString();
            _gstNumber = data['gstNumber']?.toString();
          });
        }
      } catch (e) {
        debugPrint("Error fetching Restaurant Settings: $e");
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;
    final role = auth.role;
    
    return Container(
      color: V2Colors.bg,
      child: Column(
        children: [
          _buildTopBar(restaurantId, role),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 1200) {
                  return Row(
                    children: [
                      if (role != UserRole.waiter) _buildColumnHistory(restaurantId),
                      _buildColumnTables(restaurantId, role),
                      _buildColumnMenu(restaurantId, role),
                      _buildColumnCart(restaurantId, role),
                    ],
                  );
                } else {
                  // Mobile/Tablet responsive layout (simplified with Tabs)
                  return _buildResponsiveLayout(context, restaurantId, role);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- REVENUE PILLS (TOP BAR) ---
  Widget _buildTopBar(String? restaurantId, UserRole role) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    final isWaiter = role == UserRole.waiter;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E0E),
        border: Border(bottom: BorderSide(color: V2Colors.border)),
      ),
      child: Row(
        children: [
          if (!widget.isAdminTab) ...[
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, size: 20, color: V2Colors.yellow),
                onPressed: () => Scaffold.of(context).openDrawer(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            isWaiter ? "⚡ YUG POS (WAITER)" : (role == UserRole.cashier ? "⚡ YUG POS (CASHIER)" : "⚡ YUG POS"), 
            style: V2Styles.logo
          ),
          const SizedBox(width: 16),
          if (restaurantId != null && !isWaiter)
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
                builder: (context, snapshot) {
                  double net = 0, dine = 0, tk = 0, del = 0, canCount = 0;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    net = (data['netCollection'] ?? 0).toDouble();
                    dine = (data['tableCollection'] ?? 0).toDouble();
                    tk = (data['takeawayCollection'] ?? 0).toDouble();
                    del = (data['deliveryCollection'] ?? 0).toDouble();
                    canCount = (data['cancelCount'] ?? 0).toDouble();
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildTopPill("Net", "₹${net.toStringAsFixed(0)}"),
                        _buildTopPill("Dine", "₹${dine.toStringAsFixed(0)}"),
                        _buildTopPill("TK", "₹${tk.toStringAsFixed(0)}"),
                        _buildTopPill("Del", "₹${del.toStringAsFixed(0)}"),
                        _buildTopPill("Can", "${canCount.toInt()}"),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _printDailyReport(restaurantId),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: V2Colors.yellow.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: V2Colors.yellow.withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.assessment, size: 12, color: V2Colors.yellow),
                                SizedBox(width: 4),
                                Text("DAILY REPORT", style: TextStyle(color: V2Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (isWaiter) const Spacer(),
          const SizedBox(width: 8),
          _buildClock(),
          const SizedBox(width: 8),
          _buildPrinterStatus(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16, color: V2Colors.yellow),
            onPressed: () => setState(() {}),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPill(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: V2Colors.s3,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V2Colors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: V2Styles.tpill,
          children: [
            TextSpan(text: "$label: "),
            TextSpan(text: value, style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildClock() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        return Text(
          DateFormat('HH:mm:ss').format(DateTime.now()),
          style: const TextStyle(color: V2Colors.muted, fontSize: 10),
        );
      },
    );
  }

  Widget _buildPrinterStatus() {
    final printerService = context.watch<UsbPrinterService>();
    final isConnected = printerService.isConnected;
    final device = printerService.selectedDevice;

    return InkWell(
      onTap: () => _showPrinterSelectionDialog(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isConnected ? V2Colors.green.withOpacity(0.1) : V2Colors.s3,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isConnected ? V2Colors.green.withOpacity(0.5) : V2Colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.print, size: 14, color: isConnected ? V2Colors.green : V2Colors.muted),
            const SizedBox(width: 4),
            Text(
              isConnected ? (device?.name ?? "Ready") : "No Printer",
              style: TextStyle(
                color: isConnected ? V2Colors.green : V2Colors.muted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrinterSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => Consumer<UsbPrinterService>(
        builder: (context, printer, _) => AlertDialog(
          backgroundColor: V2Colors.s1,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Select Printer", style: TextStyle(color: Colors.white)),
              if (printer.isScanning)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  icon: const Icon(Icons.refresh, color: V2Colors.yellow),
                  onPressed: () => printer.scan(),
                ),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (printer.devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("No USB printers found", style: TextStyle(color: V2Colors.muted)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: printer.devices.length,
                      itemBuilder: (context, index) {
                        final device = printer.devices[index];
                        final isSelected = printer.selectedDevice?.address == device.address;
                        return ListTile(
                          onTap: () async {
                            await printer.selectDevice(device);
                            if (mounted) Navigator.pop(context);
                          },
                          leading: Icon(Icons.print, color: isSelected ? V2Colors.green : Colors.white54),
                          title: Text(device.name ?? "Unknown", style: const TextStyle(color: Colors.white)),
                          subtitle: Text(device.address ?? "", style: const TextStyle(color: V2Colors.muted, fontSize: 10)),
                          trailing: isSelected ? const Icon(Icons.check_circle, color: V2Colors.green) : null,
                        );
                      },
                    ),
                  ),
                const Divider(color: V2Colors.border),
                TextButton(
                  onPressed: () => printer.disconnect(),
                  child: const Text("Disconnect Current", style: TextStyle(color: V2Colors.red)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printDailyReport(String restaurantId) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    
    try {
      final doc = await _firestore.collection('daily_collections').doc(docId).get();
      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No collection data for today yet."), backgroundColor: V2Colors.orange));
        }
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final printerService = context.read<UsbPrinterService>();
      final auth = context.read<AuthService>();

      if (printerService.hasSavedPrinter || printerService.isConnected) {
        final bytes = await ReportService.generateDailyCollectionBytes(
          data: data,
          hotelName: auth.restaurantName ?? "YUG POS",
        );
        await ReportService.printBytesIsolated(printerService, bytes);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Printing Daily Report (Direct)..."), backgroundColor: V2Colors.green));
        }
      } else {
        await ReportService.printDailyCollection(
          data: data,
          restaurantName: auth.restaurantName ?? "YUG POS",
          dateStr: today,
        );
      }
    } catch (e) {
      debugPrint("Daily Report Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Report Error: $e"), backgroundColor: V2Colors.red));
      }
    }
  }

  // --- COL 1: TABLES ---
  Widget _buildColumnTables(String? restaurantId, UserRole role) {
    final isWaiter = role == UserRole.waiter;
    return Container(
      width: isWaiter ? 260 : 200,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: V2Colors.border)),
      ),
      child: Column(
        children: [
          _buildColHead("TABLES", onAdd: () => _showAddTableDialog()),
          _buildZoneTabs(restaurantId),
          Expanded(child: _buildTableGrid(restaurantId)),
        ],
      ),
    );
  }

  Widget _buildColHead(String title, {VoidCallback? onAdd}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: const Color(0xFF111111),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: V2Styles.colTitle),
          if (onAdd != null)
            InkWell(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: V2Colors.yellow,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text("+ Add", style: TextStyle(color: Color(0xFF111111), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildZoneTabs(String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        final sections = <String>{};
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final section = (doc.data() as Map<String, dynamic>)['section'] as String?;
            if (section != null && section.isNotEmpty) sections.add(section);
          }
        }
        final list = sections.toList()..sort();
        
        return Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: list.map((s) => Expanded(
              child: InkWell(
                onTap: () => setState(() => _selectedZone = s),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: _selectedZone == s ? V2Colors.yellow : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _selectedZone == s ? V2Colors.yellow : V2Colors.border),
                  ),
                  child: Text(
                    s,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _selectedZone == s ? const Color(0xFF111111) : V2Colors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )).toList(),
          ),
        );
      },
    );
  }

  Widget _buildTableGrid(String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('section', isEqualTo: _selectedZone)
        .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final tables = snapshot.data!.docs.map((d) => TableModel.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();
        tables.sort(TableModel.compareByName);

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 1.2,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final t = tables[index];
            final isOcc = t.status != TableStatus.available;
            final isSel = context.watch<CartProvider>().tableId == t.id;

            return InkWell(
              onTap: () {
                if (isOcc) {
                  _showTableOptions(t);
                } else {
                  context.read<CartProvider>().setTable(t.id, t.name);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isOcc ? const Color(0xFF1C1810) : V2Colors.s2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSel ? V2Colors.yellow : (isOcc ? const Color(0xFF3A2A10) : V2Colors.border),
                    width: isSel ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(t.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isOcc ? V2Colors.orange : V2Colors.text)),
                    Text(isOcc ? "Busy" : "Free", style: TextStyle(fontSize: 9, color: isOcc ? V2Colors.orange : V2Colors.muted)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTableOptions(TableModel table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: V2Colors.s1,
        title: Text("Table ${table.name}", style: const TextStyle(color: Colors.white)),
        content: const Text("What would you like to do?", style: TextStyle(color: V2Colors.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _cancelOrder(table);
            },
            child: const Text("Cancel Order", style: TextStyle(color: V2Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _quickSettleTable(table);
            },
            child: const Text("Print & Bill", style: TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (table.currentOrderId != null) {
                context.read<CartProvider>().setActiveOrder(
                  table.currentOrderId!,
                  type: OrderType.dineIn,
                  tableName: table.name,
                  tableId: table.id,
                );
              } else {
                context.read<CartProvider>().setTable(table.id, table.name);
              }
            },
            child: const Text("Add More Items"),
          ),
        ],
      ),
    );
  }

  Future<void> _quickSettleTable(TableModel table) async {
    if (table.currentOrderId == null) return;
    try {
      final doc = await _firestore.collection('orders').doc(table.currentOrderId).get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return;
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final subtotal = (data['subtotal'] ?? 0).toDouble();
      _showBillingDialog(
        items: items,
        subtotal: subtotal,
        orderType: 'dineIn',
        tableId: table.id,
        tableName: table.name,
        orderId: table.currentOrderId,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fetch Error: $e"), backgroundColor: V2Colors.red));
    }
  }

  Future<void> _cancelOrder(TableModel table) async {
    try {
      final restaurantId = context.read<AuthService>().restaurantId;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final collRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");

      final batch = _firestore.batch();
      batch.update(_firestore.collection('tables').doc(table.id), {
        'status': 'available',
        'currentOrderId': null,
      });
      if (table.currentOrderId != null) {
        batch.update(_firestore.collection('orders').doc(table.currentOrderId), {'status': 'cancelled'});
        batch.set(collRef, {
          'cancelCount': FieldValue.increment(1),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order Cancelled Successfully"), backgroundColor: V2Colors.orange));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cancel Error: $e"), backgroundColor: V2Colors.red));
    }
  }

  void _showAddTableDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: V2Colors.s1,
        title: const Text("Add New Table", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Table Name/Number",
            hintStyle: TextStyle(color: V2Colors.muted),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: V2Colors.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                final restaurantId = context.read<AuthService>().restaurantId;
                await _firestore.collection('tables').add({
                  'name': nameCtrl.text.trim(),
                  'section': _selectedZone,
                  'status': 'available',
                  'capacity': 4,
                  'restaurantId': restaurantId,
                });
                if (mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: V2Colors.yellow),
            child: const Text("Create", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // --- COL 2: MENU ---
  Widget _buildColumnMenu(String? restaurantId, UserRole role) {
    final cart = context.watch<CartProvider>();
    final needsTable = cart.orderType == OrderType.dineIn && cart.tableId == null;
    final isWaiter = role == UserRole.waiter;

    return Expanded(
      flex: isWaiter ? 2 : 3,
      child: Container(
        decoration: const BoxDecoration(border: Border(right: BorderSide(color: V2Colors.border))),
        child: Column(
          children: [
            _buildOrderTypeTabs(),
            _buildSearchBar(),
            _buildCategoryTabs(restaurantId),
            Expanded(child: _buildMenuGrid(restaurantId, needsTable, role)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTypeTabs() {
    final curType = context.watch<CartProvider>().orderType;
    return Row(
      children: [
        _buildOTab("Dine In", Icons.restaurant, OrderType.dineIn, curType == OrderType.dineIn),
        _buildOTab("Takeaway", Icons.shopping_bag, OrderType.takeaway, curType == OrderType.takeaway),
        _buildOTab("Delivery", Icons.delivery_dining, OrderType.delivery, curType == OrderType.delivery),
      ],
    );
  }

  Widget _buildOTab(String label, IconData icon, OrderType type, bool isSel) {
    return Expanded(
      child: InkWell(
        onTap: () => context.read<CartProvider>().setOrderType(type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSel ? V2Colors.yellow : Colors.transparent, width: 2)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 14, color: isSel ? V2Colors.yellow : V2Colors.muted),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: isSel ? V2Colors.yellow : V2Colors.muted, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: V2Colors.s2,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: V2Colors.s3,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: V2Colors.border),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: V2Colors.text, fontSize: 11),
          decoration: const InputDecoration(
            hintText: "🔍 Search menu...",
            hintStyle: TextStyle(color: V2Colors.muted, fontSize: 11),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('menu_categories').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        final cats = ['All'];
        if (snapshot.hasData) {
          cats.addAll(snapshot.data!.docs.map((d) => d['name'] as String));
        }
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: cats.map((c) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(c, style: TextStyle(fontSize: 9, color: _selectedCategory == c ? Colors.black : V2Colors.muted, fontWeight: FontWeight.bold)),
                selected: _selectedCategory == c,
                onSelected: (v) => setState(() => _selectedCategory = c),
                backgroundColor: Colors.transparent,
                selectedColor: V2Colors.yellow,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: V2Colors.border)),
                showCheckmark: false,
              ),
            )).toList(),
          ),
        );
      },
    );
  }

  Widget _buildMenuGrid(String? restaurantId, bool needsTable, UserRole role) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('menu_items').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var items = snapshot.data!.docs.map((d) => MenuItem.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();
        
        if (_selectedCategory != 'All') {
          items = items.where((i) => i.category == _selectedCategory).toList();
        }
        if (_searchQuery.isNotEmpty) {
          items = items.where((i) => i.name.toLowerCase().contains(_searchQuery)).toList();
        }

        final cart = context.read<CartProvider>();
        final isWaiter = role == UserRole.waiter;

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWaiter ? 5 : 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: isWaiter ? 0.85 : 0.9,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              onTap: needsTable ? () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("⚠️ Please select a table first!"),
                  backgroundColor: V2Colors.red,
                  duration: Duration(seconds: 1),
                ));
              } : () => cart.addItem(item),
              child: Container(
                decoration: V2Styles.cardDecoration,
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("🍽", style: TextStyle(fontSize: isWaiter ? 14 : 20)),
                    const SizedBox(height: 2),
                    Text(
                      item.name, 
                      textAlign: TextAlign.center, 
                      style: TextStyle(fontSize: isWaiter ? 9 : 10, fontWeight: FontWeight.bold, height: 1.1), 
                      maxLines: 2, 
                      overflow: TextOverflow.ellipsis
                    ),
                    const SizedBox(height: 2),
                    Text("₹${item.price.toStringAsFixed(0)}", style: TextStyle(fontSize: isWaiter ? 10 : 11, color: V2Colors.yellow, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- COL 3: CART ---
  Widget _buildColumnCart(String? restaurantId, UserRole role) {
    final cart = context.watch<CartProvider>();
    final isWaiter = role == UserRole.waiter;
    return Container(
      width: isWaiter ? 300 : 250,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: V2Colors.border)),
      ),
      child: Column(
        children: [
          _buildColHead("CART"),
          _buildCartInfo(cart),
          if (cart.orderType != OrderType.dineIn) _buildCustomerInputs(),
          Expanded(child: _buildCartList(cart)),
          _buildCartFooter(cart),
        ],
      ),
    );
  }

  Widget _buildCartInfo(CartProvider cart) {
    String label = cart.orderType == OrderType.dineIn 
      ? (cart.tableName != null ? "Table ${cart.tableName}" : "Select Table")
      : "Order #NEW";
    Color badgeColor = cart.orderType == OrderType.dineIn ? Colors.blue : (cart.orderType == OrderType.takeaway ? Colors.green : Colors.red);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: V2Colors.s2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold, fontSize: 11)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(cart.orderType.name.toUpperCase(), style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInputs() {
    final cart = context.watch<CartProvider>();
    final isTakeaway = cart.orderType == OrderType.takeaway;
    final isDelivery = cart.orderType == OrderType.delivery;
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: V2Colors.border))),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => cart.setCustomerName(v),
            style: const TextStyle(fontSize: 11),
            decoration: const InputDecoration(
              isDense: true,
              hintText: "Customer Name", 
              hintStyle: TextStyle(fontSize: 11, color: V2Colors.muted),
              border: InputBorder.none,
            ),
          ),
          if (isTakeaway || isDelivery) ...[
            const Divider(color: V2Colors.border, height: 1),
            TextField(
              onChanged: (v) => cart.setCustomerContact(v),
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                hintText: "Contact Number", 
                hintStyle: TextStyle(fontSize: 11, color: V2Colors.muted),
                border: InputBorder.none,
              ),
            ),
          ],
          if (isDelivery) ...[
            const Divider(color: V2Colors.border, height: 1),
            TextField(
              onChanged: (v) => cart.setDeliveryAddress(v),
              maxLines: 2,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                hintText: "Delivery Address", 
                hintStyle: TextStyle(fontSize: 11, color: V2Colors.muted),
                border: InputBorder.none,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCartList(CartProvider cart) {
    if (cart.items.isEmpty) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Cart is empty", style: TextStyle(color: V2Colors.muted, fontSize: 11)),
          Text("Tap items to add", style: TextStyle(color: Color(0xFF444444), fontSize: 9)),
        ],
      );
    }
    return ListView.builder(
      itemCount: cart.items.length,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemBuilder: (context, index) {
        final i = cart.items[index];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF222222)))),
          child: Row(
            children: [
              Expanded(child: Text(i.item.name, style: const TextStyle(fontSize: 11))),
              Row(
                children: [
                  _buildQtyBtn("-", () => context.read<CartProvider>().updateQuantity(i, i.quantity - 1)),
                  const SizedBox(width: 8),
                  Text("${i.quantity}", style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 8),
                  _buildQtyBtn("+", () => context.read<CartProvider>().updateQuantity(i, i.quantity + 1)),
                ],
              ),
              const SizedBox(width: 12),
              Text("₹${(i.item.price * i.quantity).toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, color: V2Colors.yellow, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQtyBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 18, height: 18,
        decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(4), border: Border.all(color: V2Colors.border)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: V2Colors.text, fontSize: 12)),
      ),
    );
  }

  Widget _buildCartFooter(CartProvider cart) {
    final subtotal = cart.totalAmount;
    final tax = subtotal * (_gstPercentage / 100);
    final total = subtotal + tax;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2Colors.border))),
      child: Column(
        children: [
          _buildPriceRow("Subtotal", "₹${subtotal.toStringAsFixed(0)}"),
          if (_gstPercentage > 0) 
            _buildPriceRow("GST (${_gstPercentage.toStringAsFixed(0)}%)", "₹${tax.toStringAsFixed(2)}"),
          const SizedBox(height: 4),
          _buildPriceRow("TOTAL", "₹${total.toStringAsFixed(0)}", isTotal: true),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildActionBtn("✕ Clear", V2Colors.red, () => cart.clearCart())),
              const SizedBox(width: 4),
              Expanded(child: _buildActionBtn("✓ Place", V2Colors.green, () => _placeOrder(cart))),
            ],
          ),
          const SizedBox(height: 4),
          _buildActionBtn("🖨 Bill", V2Colors.yellow, () => _printBill(cart), isFull: true),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String val, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isTotal ? V2Colors.yellow : V2Colors.muted, fontSize: isTotal ? 13 : 11, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(val, style: TextStyle(color: isTotal ? V2Colors.yellow : V2Colors.muted, fontSize: isTotal ? 13 : 11, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color, VoidCallback onTap, {bool isFull = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        width: isFull ? double.infinity : null,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: color == V2Colors.yellow ? const Color(0xFF111111) : color, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- COL 4: HISTORY ---
  Widget _buildColumnHistory(String? restaurantId) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: V2Colors.border))),
      child: Column(
        children: [
          _buildColHead("HISTORY"),
          _buildHistoryFilters(),
          Expanded(child: _buildHistoryList(restaurantId)),
        ],
      ),
    );
  }

  Widget _buildHistoryFilters() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: V2Colors.s2,
      child: Column(
        children: [
          Row(
            children: [
              _buildHTypeBtn("all", "ALL"),
              _buildHTypeBtn("table", "TBL"),
              _buildHTypeBtn("takeaway", "TK"),
              _buildHTypeBtn("delivery", "DEL"),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildHFilterBtn("active", "ACTIVE"),
              _buildHFilterBtn("billed", "BILLED"),
              _buildHFilterBtn("cancelled", "CANCELLED"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHTypeBtn(String val, String label) {
    final isSel = _hTab == val;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _hTab = val),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: isSel ? V2Colors.yellow : V2Colors.s3, borderRadius: BorderRadius.circular(4)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isSel ? Colors.black : V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildHFilterBtn(String val, String label) {
    final isSel = _hFilter == val;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _hFilter = val),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: isSel ? V2Colors.yellow : V2Colors.s3, borderRadius: BorderRadius.circular(4)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isSel ? Colors.black : V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildHistoryList(String? restaurantId) {
    Query q = _firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId);
    
    if (_hTab != 'all') q = q.where('orderType', isEqualTo: _hTab == 'table' ? 'dineIn' : _hTab);
    
    // Filtering active status separately in stream since Firestore doesn't support 'not-in' with other filters well
    return StreamBuilder<QuerySnapshot>(
      stream: q.orderBy('createdAt', descending: true).limit(50).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final list = snapshot.data!.docs.where((doc) {
          final o = doc.data() as Map<String, dynamic>;
          final status = o['status'] ?? 'new';
          bool typeMatch = true; // Already filtered by query
          bool statusMatch = false;
          if (_hFilter == 'active') {
            statusMatch = status != 'billed' && status != 'done' && status != 'cleared' && status != 'cancelled';
          } else {
            statusMatch = status == _hFilter;
          }
          return typeMatch && statusMatch;
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final doc = list[index];
            final o = doc.data() as Map<String, dynamic>;
            return _buildOrderCard(doc.id, o);
          },
        );
      },
    );
  }

  Widget _buildOrderCard(String id, Map<String, dynamic> o) {
    final status = o['status'] ?? 'new';
    final nxtMap = {'new': 'Preparing', 'preparing': 'Ready', 'ready': 'Done'};
    final canAdv = nxtMap.containsKey(status);
    final cart = context.read<CartProvider>();
    
    final statusColor = status == 'new' ? V2Colors.yellow : (status == 'preparing' ? V2Colors.orange : (status == 'ready' ? V2Colors.green : (status == 'cancelled' ? V2Colors.red : V2Colors.muted)));
    final tokenNo = o['tokenNo'];
    final typeStr = o['orderType'] ?? 'dineIn';
    final orderType = OrderType.values.firstWhere((e) => e.name == typeStr, orElse: () => OrderType.dineIn);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: V2Styles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text("#${id.substring(0, 4).toUpperCase()}", style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold, fontSize: 11)),
                  if (tokenNo != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: V2Colors.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: Text("Token: $tokenNo", style: const TextStyle(color: V2Colors.yellow, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.visibility, size: 14, color: V2Colors.muted),
                    padding: const EdgeInsets.only(left: 8),
                    constraints: const BoxConstraints(),
                    onPressed: () => _showOrderDetailDialog(id, o),
                    tooltip: "View Details",
                  ),
                ],
              ),
              Row(
                children: [
                  if (status != 'billed' && status != 'done' && status != 'cancelled' && status != 'cleared')
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 16, color: V2Colors.yellow),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        cart.setActiveOrder(
                          id, 
                          token: tokenNo is int ? tokenNo : null,
                          type: orderType,
                          tableName: o['tableName']
                        );
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text("Adding items to Order ${tokenNo ?? id.substring(0,4)}"),
                          backgroundColor: V2Colors.yellow,
                          duration: const Duration(seconds: 2),
                        ));
                      },
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: V2Colors.border, borderRadius: BorderRadius.circular(4)),
                    child: Text(o['orderType']?.toString().toUpperCase() ?? "DINE-IN", style: const TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(o['tableName'] ?? o['customerName'] ?? 'Customer', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              Text("₹${o['totalAmount']?.toStringAsFixed(0) ?? 0}", style: const TextStyle(color: V2Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          Text(
            ((o['items'] as List?) ?? []).map((i) => "${i['name']}").join(", "),
            style: const TextStyle(color: Color(0xFF888888), fontSize: 9.5),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(status.toString().toUpperCase(), style: TextStyle(color: V2Colors.muted, fontSize: 9)),
                  const SizedBox(width: 6),
                  if (status == 'billed')
                    Text("S: ${DateFormat('HH:mm').format(_getDateTime(o['createdAt']))} | E: ${DateFormat('HH:mm').format(_getDateTime(o['billedAt']))}", 
                         style: const TextStyle(color: V2Colors.yellow, fontSize: 8.5, fontWeight: FontWeight.bold))
                  else
                    Text("S: ${DateFormat('HH:mm').format(_getDateTime(o['createdAt']))}", style: const TextStyle(color: Colors.white38, fontSize: 8.5)),
                  const SizedBox(width: 8),
                  if (status != 'done' && status != 'cancelled' && status != 'billed' && status != 'cleared' && orderType != OrderType.dineIn)
                    InkWell(
                      onTap: () => _showSettleDialogFromHistory(id, o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: V2Colors.green, borderRadius: BorderRadius.circular(4)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 10, color: Colors.white),
                            SizedBox(width: 4),
                            Text("PAY & BILL", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  if (canAdv)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InkWell(
                        onTap: () => _advanceOrder(id, status),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: V2Colors.yellow, borderRadius: BorderRadius.circular(4)),
                          child: Text("→ ${nxtMap[status]}", style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOrderDetailDialog(String id, Map<String, dynamic> o) {
    final status = o['status'] ?? 'new';
    final items = (o['items'] as List?) ?? [];
    final total = o['totalAmount'] ?? 0.0;
    final createdAt = (o['createdAt'] as Timestamp?)?.toDate();
    final timeStr = createdAt != null ? DateFormat('hh:mm a').format(createdAt) : 'N/A';
    final type = o['orderType'] ?? 'dineIn';
    final cName = o['customerName'];
    final cPhone = o['customerPhone'];
    final address = o['deliveryAddress'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: V2Colors.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: V2Colors.border)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Order details #${id.substring(0, 6).toUpperCase()}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text("Placed at $timeStr", style: const TextStyle(color: V2Colors.muted, fontSize: 10)),
              ],
            ),
            IconButton(icon: const Icon(Icons.close, color: V2Colors.muted, size: 20), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("STATUS", style: TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
                        Text(status.toString().toUpperCase(), style: TextStyle(color: status == 'billed' ? V2Colors.green : V2Colors.yellow, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text("TYPE", style: TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
                        Text(type.toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              if (type == 'takeaway' || type == 'delivery') ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("CUSTOMER INFO", style: TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text(cName ?? (type == 'delivery' ? 'Delivery Customer' : 'Takeaway'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      if (cPhone != null && cPhone.toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text("📞 $cPhone", style: const TextStyle(color: V2Colors.yellow, fontSize: 12)),
                        ),
                      if (type == 'delivery' && address != null && address.toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(color: Colors.white10),
                              const Text("DELIVERY ADDRESS", style: TextStyle(color: V2Colors.muted, fontSize: 7, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(address.toString(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("ITEMS", style: TextStyle(color: V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(color: V2Colors.border, height: 16),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Row(
                      children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(4)),
                          child: Center(child: Text("${item['quantity']}x", style: const TextStyle(color: V2Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(item['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13))),
                        Text("₹${(item['price'] * item['quantity']).toStringAsFixed(0)}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: V2Colors.yellow, thickness: 0.5),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL AMOUNT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _placeOrder(CartProvider cart) async {
    if (cart.items.isEmpty) return;
    final isDineIn = cart.orderType == OrderType.dineIn;
    if (isDineIn && cart.tableId == null) return;
    
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;

    try {
      final batch = _firestore.batch();
      final isNewOrder = cart.activeOrderId == null;
      final orderId = cart.activeOrderId ?? _firestore.collection('orders').doc().id;
      final orderRef = _firestore.collection('orders').doc(orderId);
      
      int? tokenNo = cart.activeTokenNo;
      if (isNewOrder && (cart.orderType == OrderType.takeaway || cart.orderType == OrderType.delivery)) {
        // Simple token increment (could be smarter)
        tokenNo = (DateTime.now().millisecondsSinceEpoch % 1000);
      }

      final kotTimestamp = DateTime.now().millisecondsSinceEpoch;
      final newItems = cart.items.map((i) => {
        'name': i.item.name,
        'price': i.item.price,
        'quantity': i.quantity,
        'category': i.item.category ?? 'General',
        'kotTimestamp': kotTimestamp,
      }).toList();

      final subtotal = cart.totalAmount;
      final total = subtotal * 1.05;

      if (isNewOrder) {
        batch.set(orderRef, {
          'restaurantId': restaurantId,
          'items': newItems,
          'totalAmount': total,
          'subtotal': subtotal,
          'status': 'new',
          'createdAt': FieldValue.serverTimestamp(),
          'orderType': cart.orderType.name,
          'tableName': isDineIn ? cart.tableName : (cart.orderType == OrderType.takeaway ? "Takeaway" : "Delivery"),
          'tableId': cart.tableId,
          if (tokenNo != null) 'tokenNo': tokenNo,
          'customerName': cart.customerName,
          'customerContact': cart.customerContact,
          'deliveryAddress': cart.deliveryAddress,
        });

        if (isDineIn && cart.tableId != null) {
          batch.update(_firestore.collection('tables').doc(cart.tableId), {
            'status': 'occupied',
            'currentOrderId': orderId,
          });
        }
      } else {
        batch.update(orderRef, {
          'items': FieldValue.arrayUnion(newItems),
          'totalAmount': FieldValue.increment(total),
          'subtotal': FieldValue.increment(subtotal),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Create KOT
      final kotRef = _firestore.collection('kots').doc();
      final kotData = {
        'restaurantId': restaurantId,
        'orderId': orderId,
        if (tokenNo != null) 'tokenNo': tokenNo,
        'tableId': isDineIn ? cart.tableId : cart.orderType.name,
        'tableName': isDineIn ? (cart.tableName ?? 'Table') : (cart.orderType == OrderType.takeaway ? "Takeaway" : "Delivery"),
        'items': newItems.map((i) => {'name': i['name'], 'quantity': i['quantity']}).toList(),
        'waiterName': 'POS Dashboard',
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      batch.set(kotRef, kotData);

      await batch.commit();

      // Print KOT
      try {
        final printerService = context.read<UsbPrinterService>();
        if (printerService.hasSavedPrinter || printerService.isConnected) {
          final bytes = await ReportService.generateKOTBytes(kotData);
          await ReportService.printBytesIsolated(printerService, bytes);
        } else {
          await ReportService.printKOTReceipt(kotData, orderId);
        }
      } catch (e) { debugPrint("KOT Print Error: $e"); }

      cart.clearCart();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isNewOrder ? "Order placed!" : "Items added!"), backgroundColor: V2Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: V2Colors.red));
    }
  }

  Future<void> _advanceOrder(String orderId, String currentStatus) async {
    String nextStatus;
    switch (currentStatus) {
      case 'new': nextStatus = 'preparing'; break;
      case 'preparing': nextStatus = 'ready'; break;
      case 'ready': nextStatus = 'done'; break;
      default: return;
    }
    try {
      await _firestore.collection('orders').doc(orderId).update({'status': nextStatus});
      if (nextStatus == 'done') {
        final doc = await _firestore.collection('orders').doc(orderId).get();
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data['orderType'] == 'dineIn' && data['tableId'] != null) {
          await _firestore.collection('tables').doc(data['tableId']).update({'status': 'available', 'currentOrderId': null});
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Advance Error: $e"), backgroundColor: V2Colors.red));
    }
  }

  void _printBill(CartProvider cart) {
    if (cart.items.isEmpty) return;
    _showBillingDialog(
      items: cart.items.map((i) => i.item.toMap()..['quantity'] = i.quantity).toList(),
      subtotal: cart.totalAmount,
      orderType: cart.orderType.name,
      tableId: cart.tableId,
      tableName: cart.tableName ?? 'Takeaway',
      onComplete: () => cart.clearCart(),
      orderId: cart.activeOrderId,
    );
  }

  Future<void> _showBillingDialog({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required String orderType,
    String? tableId,
    required String tableName,
    VoidCallback? onComplete,
    String? orderId,
  }) async {
    // 1. Fetch GST Setting
    final resId = context.read<AuthService>().restaurantId;
    double gstPercent = 0;
    String? gstNumber;
    if (resId != null) {
      final doc = await _firestore.collection('restaurants').doc(resId).get();
      if (doc.exists) {
        gstPercent = (doc.data()?['gstPercentage'] ?? 0).toDouble();
        gstNumber = doc.data()?['gstNumber'];
      }
    }

    String selectedMode = 'Cash';
    final scCtrl = TextEditingController();
    final dsCtrl = TextEditingController();
    bool scIsPercent = false; // Changed to false for Rupees
    bool dsIsPercent = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double scVal = double.tryParse(scCtrl.text) ?? 0;
          double dsVal = double.tryParse(dsCtrl.text) ?? 0;
          double scAmt = scIsPercent ? (subtotal * scVal / 100) : scVal;
          double subtotalWithSC = subtotal + scAmt;
          double dsAmt = dsIsPercent ? (subtotalWithSC * dsVal / 100) : dsVal;
          double taxableAmount = subtotalWithSC - dsAmt;
          double gstAmt = taxableAmount * (gstPercent / 100);
          double total = taxableAmount + gstAmt;

          return AlertDialog(
            backgroundColor: V2Colors.s1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: V2Colors.border)),
            title: Text("Settle $tableName", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 350,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          _buildPriceRow("Subtotal", "₹${subtotal.toStringAsFixed(0)}"),
                          if (scAmt > 0) _buildPriceRow("Srv Charge", "+₹${scAmt.toStringAsFixed(2)}"),
                          if (dsAmt > 0) _buildPriceRow("Discount", "-₹${dsAmt.toStringAsFixed(2)}"),
                          if (gstAmt > 0) _buildPriceRow("GST (${gstPercent.toStringAsFixed(0)}%)", "+₹${gstAmt.toStringAsFixed(2)}"),
                          const Divider(color: V2Colors.border, height: 20),
                          _buildPriceRow("TOTAL", "₹${total.toStringAsFixed(2)}", isTotal: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    _buildBillingInput(
                      label: "Service Charge",
                      controller: scCtrl,
                      isPercent: false,
                      showToggle: false, // Hide toggle for SC
                      onToggle: () {},
                      onChanged: (v) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _buildBillingInput(
                      label: "Discount",
                      controller: dsCtrl,
                      isPercent: dsIsPercent,
                      onToggle: () => setDialogState(() => dsIsPercent = !dsIsPercent),
                      onChanged: (v) => setDialogState(() {}),
                    ),
                    
                    const SizedBox(height: 24),
                    const Text("PAYMENT MODE", style: TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Row(
                      children: ['Cash', 'UPI', 'Card'].map((m) => Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedMode = m),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedMode == m ? V2Colors.yellow : V2Colors.s3,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(m, textAlign: TextAlign.center, style: TextStyle(color: selectedMode == m ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                onPressed: () => _processBilling(
                  items: items, subtotal: subtotal, paymentMode: selectedMode,
                  orderType: orderType, tableId: tableId, tableName: tableName, onComplete: onComplete,
                  existingOrderId: orderId,
                  serviceCharge: scAmt,
                  discount: dsAmt,
                  gst: gstAmt,
                  gstPercentage: gstPercent,
                  gstNumber: gstNumber ?? "",
                ),
                style: ElevatedButton.styleFrom(backgroundColor: V2Colors.green, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                child: const Text("Process & Print"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBillingInput({
    required String label,
    required TextEditingController controller,
    required bool isPercent,
    bool showToggle = true, // Added visibility control
    required VoidCallback onToggle,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          height: 36,
          decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(6), border: Border.all(color: V2Colors.border)),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: "0",
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
              if (showToggle)
                InkWell(
                  onTap: onToggle,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: V2Colors.border, borderRadius: BorderRadius.only(topRight: Radius.circular(5), bottomRight: Radius.circular(5))),
                    alignment: Alignment.center,
                    child: Text(isPercent ? "%" : "₹", style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold)),
                  ),
                )
              else
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: const Text("₹", style: TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _processBilling({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required String paymentMode,
    required String orderType,
    String? tableId,
    required String tableName,
    VoidCallback? onComplete,
    String? existingOrderId,
    double serviceCharge = 0,
    double discount = 0,
    double gst = 0,
    double gstPercentage = 0,
    String gstNumber = "",
  }) async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;
    try {
      final receiptNo = await _nextReceiptNoNonTxn(restaurantId);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final total = subtotal + serviceCharge - discount;
      final batch = _firestore.batch();
      final orderRef = existingOrderId != null 
          ? _firestore.collection('orders').doc(existingOrderId)
          : _firestore.collection('orders').doc();
      
      final orderData = {
        'restaurantId': restaurantId, 
        'items': items, 
        'totalAmount': total, 
        'subtotal': subtotal,
        'serviceCharge': serviceCharge,
        'discount': discount,
        'gst': gst,
        'cgst': gst / 2,
        'sgst': gst / 2,
        'gstPercentage': gstPercentage,
        'status': 'billed', 
        'paymentMode': paymentMode, 
        'receiptNumber': receiptNo,
        'billedAt': FieldValue.serverTimestamp(),
        'orderType': orderType, 
        'tableName': tableName,
      };

      if (existingOrderId != null) {
        batch.update(orderRef, orderData);
      } else {
        orderData['createdAt'] = FieldValue.serverTimestamp();
        batch.set(orderRef, orderData);
      }
      if (tableId != null) {
        batch.update(_firestore.collection('tables').doc(tableId), {'status': 'available', 'currentOrderId': null});
      }
      final colRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");
      batch.set(colRef, {
        'restaurantId': restaurantId, 'lastUpdatedAt': FieldValue.serverTimestamp(),
        'netCollection': FieldValue.increment(total), 'billCount': FieldValue.increment(1),
        if (orderType == 'dineIn') 'tableCollection': FieldValue.increment(total),
        if (orderType == 'takeaway') 'takeawayCollection': FieldValue.increment(total),
        if (orderType == 'delivery') 'deliveryCollection': FieldValue.increment(total),
      }, SetOptions(merge: true));
      await batch.commit();

      final printerService = context.read<UsbPrinterService>();
      final billData = {
        'items': items, 'tableName': tableName, 'orderType': orderType, 'waiterName': 'POS',
        'status': 'completed', 'receiptNumber': receiptNo, 'billedAt': Timestamp.now(),
        'serviceCharge': serviceCharge, 'discount': discount, 'subtotal': subtotal,
        'gst': gst, 'cgst': gst / 2, 'sgst': gst / 2, 'gstPercentage': gstPercentage,
      };
      if (printerService.hasSavedPrinter || printerService.isConnected) {
        final bytes = await ReportService.generateFinalBillBytes(
          data: billData, 
          total: total, 
          paymentMode: paymentMode, 
          hotelName: _restaurantName ?? auth.restaurantName ?? "YUG POS",
          address: _restaurantAddress ?? "",
          gstNumber: _gstNumber ?? "",
        );
        await ReportService.printBytesIsolated(printerService, bytes);
      } else {
        await ReportService.printFinalBill(
          orderData: billData, orderId: receiptNo.toString(), subtotal: subtotal,
          serviceCharge: serviceCharge, discount: discount, total: total,
          cgst: gst / 2, sgst: gst / 2, paymentMode: paymentMode,
          hotelName: _restaurantName ?? auth.restaurantName ?? "YUG POS",
        );
      }
      if (mounted) {
        Navigator.pop(context);
        if (onComplete != null) onComplete();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Billing Error: $e"), backgroundColor: V2Colors.red));
    }
  }

  Future<int> _nextReceiptNoNonTxn(String restaurantId) async {
    final ref = _firestore.collection('receipt_counters').doc(restaurantId);
    final doc = await ref.get();
    final next = (doc.data()?['lastReceiptNo'] ?? 0) + 1;
    await ref.set({'lastReceiptNo': next}, SetOptions(merge: true));
    return next;
  }

  void _showSettleDialogFromHistory(String id, Map<String, dynamic> o) {
    _showBillingDialog(
      items: (o['items'] as List).cast<Map<String, dynamic>>(),
      subtotal: (o['subtotal'] ?? 0).toDouble(),
      orderType: o['orderType'] ?? 'dineIn',
      tableId: o['tableId'],
      tableName: o['tableName'] ?? 'Takeaway',
      onComplete: () => setState(() {}),
    );
  }

  DateTime _getDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  // --- MOBILE RESPONSIVE VIEW ---
  Widget _buildResponsiveLayout(BuildContext context, String? restaurantId, UserRole role) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: V2Colors.s1,
            child: const TabBar(
              indicatorColor: V2Colors.yellow,
              labelColor: V2Colors.yellow,
              unselectedLabelColor: V2Colors.muted,
              tabs: [
                Tab(icon: Icon(Icons.table_restaurant), text: "TABLES"),
                Tab(icon: Icon(Icons.restaurant_menu), text: "MENU"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildColumnTables(restaurantId, role),
                _buildColumnMenu(restaurantId, role),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

