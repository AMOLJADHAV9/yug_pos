import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../models/table_model.dart';
import '../models/menu_item.dart';
import '../providers/cart_provider.dart';
import '../services/report_service.dart';
import '../services/usb_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../screens/cashier/v2_styles.dart';
import '../utils/navigator_utils.dart';
import 'menu_item_card.dart';

class POSViewContent extends StatefulWidget {
  final bool isAdminTab;
  final Function(int)? onTabSelect;
  const POSViewContent({super.key, this.isAdminTab = false, this.onTabSelect});

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
  DateTime _selectedHistoryDate = DateTime.now();
  DateTime _selectedReportsDate = DateTime.now();
  double _gstPercentage = 0.0;
  String? _restaurantAddress;
  String? _restaurantName;
  String? _gstNumber;
  String? _lastRestaurantId;
  int _mobileActiveIndex = 1; // 0: History, 1: Tables/Order, 2: Cart, 3: Reports, 4: Settings
  bool _isSubmitting = false;
  bool _isProcessingBilling = false;
  bool _showMobileHistoryList = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
    final isWaiter = role == UserRole.waiter;
    
    return Container(
      color: V2Colors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLarge = constraints.maxWidth > 1200;
          
          if (isLarge) {
            return Column(
              children: [
                _buildTopBar(restaurantId, role),
                Expanded(
                  child: Row(
                    children: [
                      if (role != UserRole.waiter) _buildColumnHistory(restaurantId),
                      _buildColumnTables(restaurantId, role),
                      Expanded(flex: isWaiter ? 2 : 3, child: _buildColumnMenu(restaurantId, role)),
                      _buildColumnCart(restaurantId, role),
                    ],
                  ),
                ),
              ],
            );
          } else {
            // Mobile/Tablet responsive layout
            return Scaffold(
              key: _scaffoldKey, // Add a key to safely control drawer
              backgroundColor: V2Colors.bg,
              drawer: _buildMobileDrawer(), // Added drawer
              body: Column(
                children: [
                  _buildMobileHeader(restaurantId, role),
                  Expanded(child: _buildMobileContentView(restaurantId, role)),
                ],
              ),
              bottomNavigationBar: _buildMobileBottomNav(),
            );
          }
        },
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
            isWaiter ? " YUG POS (WAITER)" : (role == UserRole.cashier ? " YUG POS (CASHIER)" : " YUG POS"), 
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
    final isAndroid = !kIsWeb && Platform.isAndroid;
    if (isAndroid) {
      final bt = context.watch<BluetoothPrinterService>();
      final isConnected = bt.isConnected;
      final hasSaved = bt.hasSavedPrinter;
      return InkWell(
        onTap: () => _showPrinterSelectionDialog(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isConnected ? V2Colors.green.withOpacity(0.1) : (hasSaved ? Colors.orange.withOpacity(0.1) : V2Colors.s3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isConnected ? V2Colors.green.withOpacity(0.5) : (hasSaved ? Colors.orange.withOpacity(0.5) : V2Colors.border)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bluetooth, size: 14, color: isConnected ? V2Colors.green : (hasSaved ? Colors.orange : V2Colors.muted)),
              const SizedBox(width: 4),
              Text(
                isConnected ? "BT Connected" : (hasSaved ? "BT Saved" : "No Printer"),
                style: TextStyle(
                  color: isConnected ? V2Colors.green : (hasSaved ? Colors.orange : V2Colors.muted),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Non-Android: show USB status
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
    final isAndroid = !kIsWeb && Platform.isAndroid;
    if (isAndroid) {
      // ── Bluetooth Printer Setup (Android) ──
      showDialog(
        context: context,
        builder: (ctx) => Consumer<BluetoothPrinterService>(
          builder: (ctx, bt, _) => AlertDialog(
            backgroundColor: V2Colors.s1,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Bluetooth Printer", style: TextStyle(color: Colors.white, fontSize: 16)),
                if (bt.isScanning)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V2Colors.yellow))
                else
                  IconButton(
                    icon: const Icon(Icons.bluetooth_searching, color: V2Colors.yellow),
                    tooltip: "Scan for printers",
                    onPressed: () => bt.scan(),
                  ),
              ],
            ),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: bt.isConnected ? V2Colors.green.withOpacity(0.1) : (bt.hasSavedPrinter ? Colors.orange.withOpacity(0.1) : V2Colors.s3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: bt.isConnected ? V2Colors.green : (bt.hasSavedPrinter ? Colors.orange : V2Colors.border)),
                    ),
                    child: Text(
                      bt.isConnected ? "✅ Connected & Ready to Print" : (bt.hasSavedPrinter ? "🟡 Printer Saved — Tap to reconnect" : "🔴 No printer selected"),
                      style: TextStyle(
                        color: bt.isConnected ? V2Colors.green : (bt.hasSavedPrinter ? Colors.orange : V2Colors.muted),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (bt.isConnecting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: V2Colors.yellow)),
                        SizedBox(width: 8),
                        Text("Connecting...", style: TextStyle(color: V2Colors.muted)),
                      ]),
                    )
                  else if (bt.devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        "Tap the scan button (🔵) above to discover nearby Bluetooth printers.",
                        style: TextStyle(color: V2Colors.muted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: bt.devices.length,
                        itemBuilder: (ctx2, i) {
                          final dev = bt.devices[i];
                          final isSel = bt.selectedDevice?.address == dev.address;
                          return ListTile(
                            onTap: () async {
                              await bt.selectDevice(dev);
                              if (mounted) safePop(context);
                            },
                            leading: Icon(Icons.bluetooth, color: isSel ? V2Colors.green : Colors.white54),
                            title: Text(dev.name ?? "Unknown", style: const TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: Text(dev.address ?? "", style: const TextStyle(color: V2Colors.muted, fontSize: 10)),
                            trailing: isSel ? const Icon(Icons.check_circle, color: V2Colors.green) : null,
                          );
                        },
                      ),
                    ),
                  const Divider(color: V2Colors.border),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: bt.hasSavedPrinter ? () => bt.testPrint() : null,
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text("Test Print", style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: V2Colors.yellow, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                      TextButton.icon(
                        onPressed: bt.isConnected ? () => bt.disconnect() : null,
                        icon: const Icon(Icons.bluetooth_disabled, size: 16),
                        label: const Text("Disconnect", style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: V2Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    // ── USB Printer Setup (Non-Android) ──
    showDialog(
      context: context,
      builder: (context) => Consumer<UsbPrinterService>(
        builder: (context, printer, _) => AlertDialog(
          backgroundColor: V2Colors.s1,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(child: Text("Select Printer", style: TextStyle(color: Colors.white))),
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
                            if (mounted) safePop(context);
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
      final usb = context.read<UsbPrinterService>();
      final bt = context.read<BluetoothPrinterService>();
      final isAndroid = !kIsWeb && Platform.isAndroid;
      final dynamic printerService = isAndroid ? bt : usb;
      final auth = context.read<AuthService>();

      if (printerService.hasSavedPrinter || printerService.isConnected) {
        final bytes = await ReportService.generateDailyCollectionBytes(
          data: data,
          hotelName: auth.restaurantName ?? "YUG POS",
          paperSize: isAndroid ? PaperSize.mm58 : PaperSize.mm80,
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
  Widget _buildColumnTables(String? restaurantId, UserRole role, {bool isMobile = false}) {
    final isWaiter = role == UserRole.waiter;
    return Container(
      width: isMobile ? null : (isWaiter ? 280 : 240),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: isMobile ? Colors.transparent : V2Colors.border)),
      ),
      child: Column(
        children: [
          if (!isMobile) _buildColHead("TABLES", onAdd: () => _showAddTableDialog()),
          _buildZoneTabs(restaurantId, isMobile: isMobile),
          Expanded(child: _buildTableGrid(restaurantId, isMobile: isMobile)),
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

  Widget _buildZoneTabs(String? restaurantId, {bool isMobile = false}) {
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
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 8, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: list.map((s) {
                final isSelected = _selectedZone == s;
                return InkWell(
                  onTap: () => setState(() => _selectedZone = s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? V2Colors.yellow : V2Colors.s3,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? V2Colors.yellow : V2Colors.border, width: 0.5),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        color: isSelected ? Colors.black : V2Colors.muted,
                        fontSize: isMobile ? 11 : 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableGrid(String? restaurantId, {bool isMobile = false}) {
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
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 8, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isMobile ? 3 : 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: isMobile ? 1.0 : 1.2,
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
          TextButton(onPressed: () => safePop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              safePop(context);
              await _cancelOrder(table);
            },
            child: const Text("Cancel Order", style: TextStyle(color: V2Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              safePop(context);
              await _quickSettleTable(table);
            },
            child: const Text("Print & Bill", style: TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              safePop(context);
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
      final restaurantId = context.read<AuthService>().restaurantId;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Cancel Error: $e | RID: $restaurantId | OID: ${table.currentOrderId}"), 
        backgroundColor: V2Colors.red,
        duration: const Duration(seconds: 5),
      ));
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
          TextButton(onPressed: () => safePop(context), child: const Text("Cancel")),
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
                if (mounted) safePop(context);
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

    return Container(
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: V2Colors.border))),
      child: Column(
        children: [
          _buildOrderTypeTabs(),
          _buildSearchBar(),
          _buildCategoryTabs(restaurantId),
          Expanded(child: _buildMenuGrid(restaurantId, needsTable, role)),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: V2Colors.s2,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: V2Colors.s1, // Use a slightly darker color for depth
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: V2Colors.border, width: 1.5),
        ),
        child: Center(
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: V2Colors.text, fontSize: 13),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: "Search menu...",
              hintStyle: const TextStyle(color: V2Colors.muted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: V2Colors.yellow, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: V2Colors.muted,
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('menu_categories')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        final cats = ['All'];
        if (snapshot.hasData) {
          cats.addAll(snapshot.data!.docs.map((d) => d['name'] as String));
        }
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: cats.length,
            itemBuilder: (context, index) {
              final c = cats[index];
              final isSel = _selectedCategory == c;
              
              // Title case conversion
              final label = c.split(' ').map((word) {
                if (word.isEmpty) return word;
                return word[0].toUpperCase() + word.substring(1).toLowerCase();
              }).join(' ');

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _selectedCategory = c),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel ? V2Colors.yellow : V2Colors.s3,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSel ? V2Colors.yellow : V2Colors.border,
                        width: 1,
                      ),
                      boxShadow: isSel ? [
                        BoxShadow(
                          color: V2Colors.yellow.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        )
                      ] : [],
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSel ? Colors.black : V2Colors.text,
                          fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;

            return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isMobile ? 3 : 5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: isMobile ? 0.85 : 1.0,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final cartQty = cart.items.where((i) => i.item.id == item.id).fold(0, (sum, i) => sum + i.quantity);
                final isSelected = cartQty > 0;

                return MenuItemCard(
                  item: item,
                  onTap: needsTable ? () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("⚠️ Please select a table first!"),
                      backgroundColor: V2Colors.red,
                      duration: Duration(seconds: 1),
                    ));
                  } : () => cart.addItem(item),
                  isSelected: isSelected,
                  quantity: cartQty,
                  isMobile: isMobile,
                );
              },
            );
          }
        );
      },
    );
  }


  // --- COL 3: CART ---
  Widget _buildColumnCart(String? restaurantId, UserRole role, {bool isMobile = false}) {
    final cart = context.watch<CartProvider>();
    final isWaiter = role == UserRole.waiter;
    return Container(
      width: isMobile ? null : (isWaiter ? 260 : 200),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: isMobile ? Colors.transparent : V2Colors.border)),
      ),
      child: Column(
        children: [
          if (!isMobile) _buildColHead("CART"),
          _buildCartInfo(cart),
          if (cart.orderType != OrderType.dineIn && !isMobile) _buildCustomerInputs(),
          Expanded(child: _buildCartList(cart, isMobile: isMobile)),
          _buildCartFooter(cart, isMobile: isMobile, isWaiter: isWaiter),
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
          Expanded(
            child: Text(label, 
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold, fontSize: 11)
            ),
          ),
          const SizedBox(width: 8),
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

  Widget _buildCartList(CartProvider cart, {bool isMobile = false}) {
    if (cart.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: isMobile ? 48 : 32, color: V2Colors.s3),
            const SizedBox(height: 12),
            const Text("Cart is empty", style: TextStyle(color: V2Colors.muted, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text("Tap items to add", style: TextStyle(color: Color(0xFF444444), fontSize: 10)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: cart.items.length,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 8),
      itemBuilder: (context, index) {
        final i = cart.items[index];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF222222)))),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: MenuItemThumb(item: i.item, placeholderIconSize: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.item.name, style: TextStyle(fontSize: isMobile ? 12 : 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    if (i.specialInstructions.isNotEmpty) 
                      Text(i.specialInstructions, style: const TextStyle(color: V2Colors.muted, fontSize: 9)),
                  ],
                ),
              ),
              Row(
                children: [
                  _buildQtyBtn("-", () => context.read<CartProvider>().updateQuantity(i, i.quantity - 1)),
                  const SizedBox(width: 10),
                  Text("${i.quantity}", style: TextStyle(fontSize: isMobile ? 13 : 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  _buildQtyBtn("+", () => context.read<CartProvider>().updateQuantity(i, i.quantity + 1)),
                ],
              ),
              const SizedBox(width: 16),
              Text("₹${(i.item.price * i.quantity).toStringAsFixed(0)}", style: TextStyle(fontSize: isMobile ? 13 : 11, color: V2Colors.yellow, fontWeight: FontWeight.bold)),
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

  Widget _buildCartFooter(CartProvider cart, {bool isMobile = false, bool isWaiter = false}) {
    final subtotal = cart.totalAmount;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 10, vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2Colors.border))),
      child: Column(
        children: [
          _buildPriceRow("Subtotal", "₹${subtotal.toStringAsFixed(0)}"),
          const SizedBox(height: 4),
          _buildPriceRow("TOTAL", "₹${subtotal.toStringAsFixed(0)}", isTotal: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildActionBtn("✕ Clear", V2Colors.red, () => cart.clearCart(), height: isMobile ? 48 : 36)),
              const SizedBox(width: 8),
              Expanded(child: _buildActionBtn("✓ Place", V2Colors.green, () => _placeOrder(cart), height: isMobile ? 48 : 36)),
            ],
          ),
          if (!isWaiter) ...[
            const SizedBox(height: 8),
            _buildActionBtn("🖨 Bill", V2Colors.yellow, () => _printBill(cart), isFull: true, height: isMobile ? 48 : 36),
          ],
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

  Widget _buildActionBtn(String label, Color color, VoidCallback onTap, {bool isFull = false, double height = 36}) {
    final isYellow = color == V2Colors.yellow;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: height,
        width: isFull ? double.infinity : null,
        decoration: BoxDecoration(
          color: isYellow ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isYellow ? color : color.withOpacity(0.3)),
        ),
        alignment: Alignment.center,
        child: Text(
          label, 
          style: TextStyle(
            color: isYellow ? Colors.black : color, 
            fontSize: height > 40 ? 13 : 11, 
            fontWeight: FontWeight.bold
          )
        ),
      ),
    );
  }

  Future<void> _selectHistoryDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedHistoryDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: V2Colors.yellow,
              onPrimary: Colors.black,
              surface: V2Colors.s2,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedHistoryDate) {
      setState(() => _selectedHistoryDate = picked);
    }
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
    final dateStr = DateUtils.isSameDay(_selectedHistoryDate, DateTime.now()) 
        ? "TODAY" 
        : DateFormat('dd MMM').format(_selectedHistoryDate).toUpperCase();

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
              const SizedBox(width: 4),
              InkWell(
                onTap: _selectHistoryDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: V2Colors.s3,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: V2Colors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 8, color: V2Colors.yellow),
                      const SizedBox(width: 4),
                      Text(dateStr, style: const TextStyle(color: V2Colors.yellow, fontSize: 8, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
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
    final start = DateTime(_selectedHistoryDate.year, _selectedHistoryDate.month, _selectedHistoryDate.day);
    final end = start.add(const Duration(days: 1));

    Query q = _firestore.collection('orders')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end));
    
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
    final nxtMap = {'new': 'Preparing', 'preparing': 'Ready'};
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
              Expanded(
                child: Row(
                  children: [
                    Text("#${id.substring(0, 4).toUpperCase()}", style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold, fontSize: 10)),
                    const SizedBox(width: 4),
                    Text(DateFormat('dd/MM').format(_getDateTime(o['createdAt'])), style: const TextStyle(color: V2Colors.muted, fontSize: 8)),
                    if (tokenNo != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: V2Colors.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                          child: Text("Token: $tokenNo", style: const TextStyle(color: V2Colors.yellow, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.visibility, size: 13, color: V2Colors.muted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showOrderDetailDialog(id, o),
                      tooltip: "View Details",
                    ),
                    if (context.read<AuthService>().role == UserRole.admin || context.read<AuthService>().role == UserRole.cashier)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 13, color: V2Colors.red),
                        padding: const EdgeInsets.only(left: 4),
                        constraints: const BoxConstraints(),
                        onPressed: () => _confirmDeleteBill(id, o),
                        tooltip: "Delete Bill",
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status != 'billed' && status != 'done' && status != 'cancelled' && status != 'cleared')
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 15, color: V2Colors.yellow),
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
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: V2Colors.border, borderRadius: BorderRadius.circular(4)),
                    child: Text(o['orderType']?.toString().toUpperCase() ?? "DINE-IN", style: const TextStyle(color: V2Colors.muted, fontSize: 7, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                orderType == OrderType.dineIn 
                    ? (o['tableName'] ?? 'Table') 
                    : (orderType == OrderType.delivery ? 'Delivery' : 'Takeaway'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
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
              Expanded(
                child: Row(
                  children: [
                    Container(width: 5, height: 5, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(status.toString().toUpperCase(), style: TextStyle(color: V2Colors.muted, fontSize: 8)),
                    const SizedBox(width: 5),
                    if (status == 'billed')
                      Expanded(
                        child: Text("S:${DateFormat('HH:mm').format(_getDateTime(o['createdAt']))} | E:${DateFormat('HH:mm').format(_getDateTime(o['billedAt']))}", 
                             style: const TextStyle(color: V2Colors.yellow, fontSize: 8, fontWeight: FontWeight.bold),
                             overflow: TextOverflow.ellipsis),
                      )
                    else
                      Text("S:${DateFormat('HH:mm').format(_getDateTime(o['createdAt']))}", style: const TextStyle(color: Colors.white38, fontSize: 8)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status != 'done' && status != 'cancelled' && status != 'billed' && status != 'cleared' && orderType != OrderType.dineIn)
                    InkWell(
                      onTap: () => _showSettleDialogFromHistory(id, o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: V2Colors.green, borderRadius: BorderRadius.circular(4)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 8, color: Colors.white),
                            SizedBox(width: 2),
                            Text("PAY", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  if (canAdv)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        onTap: () => _advanceOrder(id, status),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: V2Colors.yellow, borderRadius: BorderRadius.circular(4)),
                          child: Text("→${nxtMap[status]}", style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
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
    final cContact = o['customerContact'];
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
            IconButton(icon: const Icon(Icons.close, color: V2Colors.muted, size: 20), onPressed: () => safePop(context)),
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
                      Text(cName ?? (type.toString().toLowerCase() == 'delivery' ? 'Delivery Customer' : 'Takeaway'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      if (cContact != null && cContact.toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text("📞 $cContact", style: const TextStyle(color: V2Colors.yellow, fontSize: 12)),
                        ),
                      if (type.toString().toLowerCase() == 'delivery' && address != null && address.toString().isNotEmpty)
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
              if (context.read<AuthService>().role == UserRole.admin || context.read<AuthService>().role == UserRole.cashier) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      safePop(context);
                      _confirmDeleteBill(id, o);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: V2Colors.red.withOpacity(0.1),
                      foregroundColor: V2Colors.red,
                      side: const BorderSide(color: V2Colors.red, width: 1),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.delete_forever, size: 16),
                    label: const Text("DELETE BILL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteBill(String id, Map<String, dynamic> o) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: V2Colors.s1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: V2Colors.border)),
        title: const Text("DELETE BILL?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text(
          "This will permanently delete the bill and subtract the amount from the daily revenue report. Are you sure?",
          style: TextStyle(color: V2Colors.muted, fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => safePop(context), child: const Text("CANCEL", style: TextStyle(color: V2Colors.muted))),
          ElevatedButton(
            onPressed: () {
              safePop(context);
              _deleteBill(id, o);
            },
            style: ElevatedButton.styleFrom(backgroundColor: V2Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _deleteBill(String orderId, Map<String, dynamic> data) async {
    try {
      final auth = context.read<AuthService>();
      final restaurantId = auth.restaurantId;
      if (restaurantId == null) return;

      final billedAt = (data['billedAt'] as Timestamp?)?.toDate() ?? 
                       (data['completedAt'] as Timestamp?)?.toDate() ?? 
                       (data['createdAt'] as Timestamp?)?.toDate() ?? 
                       DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(billedAt);
      final collectionId = "${restaurantId}_$dateStr";
      final total = ((data['totalAmount'] ?? data['grandTotal'] ?? 0) as num).toDouble();

      final orderTypeStr = (data['orderType'] as String?)?.toLowerCase() ?? '';
      final orderSource = (data['orderSource'] as String?)?.toLowerCase() ?? '';
      final bool isTakeaway = orderTypeStr == 'takeaway' || data['tableName'] == 'Takeaway';
      final bool isDelivery = orderTypeStr == 'delivery' || orderSource == 'delivery';
      final bool isOnline = orderTypeStr == 'online' || orderSource == 'zomato' || orderSource == 'swiggy';

      final batch = _firestore.batch();
      batch.delete(_firestore.collection('orders').doc(orderId));

      final revUpdate = <String, dynamic>{
        'netCollection': FieldValue.increment(-total),
        'grossCollection': FieldValue.increment(-total),
        'billCount': FieldValue.increment(-1),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (isOnline) {
        revUpdate['onlineCollection'] = FieldValue.increment(-total);
        revUpdate['onlineCount'] = FieldValue.increment(-1);
      } else if (isTakeaway) {
        revUpdate['takeawayCollection'] = FieldValue.increment(-total);
        revUpdate['takeawayCount'] = FieldValue.increment(-1);
      } else if (isDelivery) {
        revUpdate['deliveryCollection'] = FieldValue.increment(-total);
        revUpdate['deliveryCount'] = FieldValue.increment(-1);
      } else {
        revUpdate['tableCollection'] = FieldValue.increment(-total);
        revUpdate['tableCount'] = FieldValue.increment(-1);
      }

      // Adjust Payment Method Totals
      final String paymentMode = (data['paymentMode'] ?? '').toString().toLowerCase();
      if (paymentMode == 'upi') {
        revUpdate['upiCollection'] = FieldValue.increment(-total);
      } else if (paymentMode == 'cash') {
        revUpdate['cashCollection'] = FieldValue.increment(-total);
      }

      batch.update(_firestore.collection('daily_collections').doc(collectionId), revUpdate);
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bill deleted and revenue adjusted."), backgroundColor: V2Colors.red));
        setState(() {}); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete Error: $e"), backgroundColor: V2Colors.red));
      }
    }
  }

  Future<void> _placeOrder(CartProvider cart) async {
    if (cart.items.isEmpty) return;
    final isDineIn = cart.orderType == OrderType.dineIn;
    if (isDineIn && cart.tableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a table for Dine-In orders")));
      return;
    }
    
    setState(() => _isSubmitting = true);

    try {
      final auth = context.read<AuthService>();
      final restaurantId = auth.restaurantId;
      if (restaurantId == null) throw Exception("Restaurant ID not found");

      // Fetch GST settings
      final settingsDoc = await _firestore.collection('settings').doc(restaurantId).get();
      final settings = settingsDoc.data();
      final double _gstPercentage = (settings?['gstPercentage'] ?? 5.0).toDouble();

      String? tableName;
      Map<String, dynamic>? tableData;
      
      if (isDineIn && cart.tableId != null) {
        final tableRef = _firestore.collection('tables').doc(cart.tableId);
        final tableDoc = await tableRef.get();
        if (tableDoc.exists) {
          tableData = tableDoc.data() as Map<String, dynamic>;
          tableName = tableData['name'];
        }
      } else {
        tableName = cart.orderType == OrderType.takeaway ? "TAKEAWAY" : "DELIVERY";
      }

      final String orderId = cart.activeOrderId ?? (isDineIn && tableData?['currentOrderId'] != null 
          ? tableData!['currentOrderId'] 
          : _firestore.collection('orders').doc().id);
      
      final orderRef = _firestore.collection('orders').doc(orderId);
      final bool isNewOrder = cart.activeOrderId == null && (tableData?['currentOrderId'] == null || !isDineIn);

      final subtotal = cart.totalAmount;
      final total = subtotal * (1 + (_gstPercentage / 100));
      final int totalItemsCount = cart.totalItems;
      final int kotTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      int kotNo = 1;
      final batch = _firestore.batch();

      if (isNewOrder) {
        batch.set(orderRef, {
          'tableId': isDineIn ? cart.tableId : null,
          'tableName': tableName ?? 'Unknown',
          'orderType': cart.orderType.name,
          'waiterName': cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter',
          'customerName': cart.customerName ?? 'Walk-in',
          'status': 'active',
          'takeawayStatus': cart.orderType == OrderType.takeaway ? 'pending' : null,
          'deliveryStatus': cart.orderType == OrderType.delivery ? 'pending' : null,
          'isDelivered': false,
          'restaurantId': restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
          'totalAmount': total,
          'subtotal': subtotal,
          'totalItems': totalItemsCount,
          'gstPercentage': _gstPercentage,
          'kotCount': 1,
          'items': cart.items.map((i) => {
            'id': i.item.id,
            'name': i.item.name,
            'price': i.item.price,
            'quantity': i.quantity,
            'category': i.item.category,
            'kotNo': 1,
            'kotTimestamp': kotTimestamp,
            'specialInstructions': i.specialInstructions,
          }).toList(),
        });
        
        if (isDineIn && cart.tableId != null) {
          batch.update(_firestore.collection('tables').doc(cart.tableId), {
            'status': 'occupied',
            'currentOrderId': orderId,
          });
        }
      } else {
        // Fetch current order to get kotCount
        final orderDoc = await orderRef.get();
        if (orderDoc.exists) {
          kotNo = (orderDoc.data()?['kotCount'] ?? 1) + 1;
        }

        batch.update(orderRef, {
          'items': FieldValue.arrayUnion(cart.items.map((i) => {
            'id': i.item.id,
            'name': i.item.name,
            'price': i.item.price,
            'quantity': i.quantity,
            'category': i.item.category,
            'kotNo': kotNo,
            'kotTimestamp': kotTimestamp,
            'specialInstructions': i.specialInstructions,
          }).toList()),
          'totalAmount': FieldValue.increment(total),
          'subtotal': FieldValue.increment(subtotal),
          'totalItems': FieldValue.increment(totalItemsCount),
          'gstPercentage': _gstPercentage,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'kotCount': kotNo,
        });
      }

      // Create KOT record
      final kotRef = _firestore.collection('kots').doc();
      final kotId = kotRef.id;
      final kNoStr = "KOT #$kotNo";

      batch.set(kotRef, {
        'restaurantId': restaurantId,
        'orderId': orderId,
        'tableId': isDineIn ? cart.tableId : null,
        'tableName': tableName ?? 'Unknown',
        'orderType': cart.orderType.name,
        'customerName': cart.customerName ?? 'Walk-in',
        'waiterName': cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter',
        'status': 'Pending',
        'kotNo': kotNo,
        'kotId': kotId,
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'specialInstructions': i.specialInstructions,
        }).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      
      // Prepare data for printing
      final kotData = {
        'tableName': tableName ?? 'Unknown',
        'customerName': cart.customerName ?? 'Walk-in',
        'waiterName': cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter',
        'cashierName': auth.userName ?? 'Staff',
        'kotNo': kotNo,
        'restaurantId': restaurantId,
        'orderType': cart.orderType.name,
        'createdAt': Timestamp.now(),
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'price': i.item.price,
        }).toList(),
      };

      final usb = context.read<UsbPrinterService>();
      final bt = context.read<BluetoothPrinterService>();
      final isAndroid = !kIsWeb && Platform.isAndroid;

      await ReportService.printKOTReceipt(
        kotData, 
        orderId, 
        printerService: isAndroid ? bt : usb,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order Placed! $kNoStr'),
          backgroundColor: V2Colors.green,
        ));
        cart.clearCart();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to place order: $e'),
          backgroundColor: V2Colors.red,
        ));
      }
    }
  }


  Future<void> _advanceOrder(String orderId, String currentStatus) async {
    String nextStatus;
    switch (currentStatus) {
      case 'new': nextStatus = 'preparing'; break;
      case 'preparing': nextStatus = 'ready'; break;
      default: return;
    }
    try {
      await _firestore.collection('orders').doc(orderId).update({'status': nextStatus});
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
      customerName: cart.customerName,
      customerContact: cart.customerContact,
      deliveryAddress: cart.deliveryAddress,
      onComplete: () => setState(() {
        cart.clearCart();
        _hFilter = 'billed';
      }),
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
    String? customerName,
    String? customerContact,
    String? deliveryAddress,
  }) async {
    // 1. Fetch GST Setting
    final resId = context.read<AuthService>().restaurantId;
    double gstPercent = 0;
    String? gstNumber;
    if (resId != null) {
      final doc = await _firestore.collection('restaurants').doc(resId).get();
      if (!mounted) return;
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
          final cart = context.read<CartProvider>();
          final displayCustName = customerName ?? cart.customerName;
          final displayCustContact = customerContact ?? cart.customerContact;
          final displayCustAddr = deliveryAddress ?? cart.deliveryAddress;

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
                          if (orderType.toLowerCase() != 'dinein') ...[
                            Row(children: [
                              const Icon(Icons.person_outline, size: 10, color: V2Colors.muted),
                              const SizedBox(width: 4),
                              Expanded(child: Text(displayCustName ?? 'Walk-in', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                            ]),
                            if (displayCustContact?.isNotEmpty ?? false)
                              Row(children: [
                                const Icon(Icons.phone_outlined, size: 10, color: V2Colors.muted),
                                const SizedBox(width: 4),
                                Text(displayCustContact!, style: const TextStyle(color: V2Colors.muted, fontSize: 9)),
                              ]),
                            if (orderType.toLowerCase() == 'delivery' && (displayCustAddr?.isNotEmpty ?? false))
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.location_on_outlined, size: 10, color: V2Colors.muted),
                                const SizedBox(width: 4),
                                Expanded(child: Text(displayCustAddr!, style: const TextStyle(color: V2Colors.muted, fontSize: 9), maxLines: 2, overflow: TextOverflow.ellipsis)),
                              ]),
                            const Divider(color: V2Colors.border, height: 16),
                          ],
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
              TextButton(onPressed: _isProcessingBilling ? null : () => safePop(context), child: const Text("Cancel")),
              ElevatedButton.icon(
                onPressed: _isProcessingBilling ? null : () async {
                  setState(() => _isProcessingBilling = true);
                  await _processBilling(
                    items: items, subtotal: subtotal, paymentMode: selectedMode,
                    orderType: orderType, tableId: tableId, tableName: tableName, onComplete: onComplete,
                    existingOrderId: orderId,
                    customerName: displayCustName,
                    customerContact: displayCustContact,
                    deliveryAddress: displayCustAddr,
                    serviceCharge: scAmt,
                    discount: dsAmt,
                    gst: gstAmt,
                    gstPercentage: gstPercent,
                    gstNumber: gstNumber ?? "",
                    sharePdf: true,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: V2Colors.yellow, 
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.share, size: 18),
                label: const Text("Share PDF"),
              ),
              ElevatedButton(
                onPressed: _isProcessingBilling ? null : () async {
                  setState(() => _isProcessingBilling = true);
                  await _processBilling(
                    items: items, subtotal: subtotal, paymentMode: selectedMode,
                    orderType: orderType, tableId: tableId, tableName: tableName, onComplete: onComplete,
                    existingOrderId: orderId,
                    customerName: displayCustName,
                    customerContact: displayCustContact,
                    deliveryAddress: displayCustAddr,
                    serviceCharge: scAmt,
                    discount: dsAmt,
                    gst: gstAmt,
                    gstPercentage: gstPercent,
                    gstNumber: gstNumber ?? "",
                  );
                },
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
    String? customerName,
    String? customerContact,
    String? deliveryAddress,
    bool sharePdf = false,
  }) async {
    final auth = context.read<AuthService>();
    final cart = context.read<CartProvider>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;
    try {
      final receiptNo = await _nextReceiptNoNonTxn(restaurantId);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final total = subtotal + serviceCharge - discount + gst;
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
        'tableName': orderType == 'dineIn' ? tableName : (orderType == 'delivery' ? 'Delivery' : 'Takeaway'),
        'customerName': customerName,
        'customerContact': customerContact,
        'deliveryAddress': deliveryAddress,
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
        'restaurantId': restaurantId, 
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'netCollection': FieldValue.increment(total), 
        'billCount': FieldValue.increment(1),
        
        // Revenue by Type
        if (orderType == 'dineIn') 'tableCollection': FieldValue.increment(total),
        if (orderType == 'takeaway') 'takeawayCollection': FieldValue.increment(total),
        if (orderType == 'delivery') 'deliveryCollection': FieldValue.increment(total),
        
        // Order Counts by Type
        if (orderType == 'dineIn') 'tableCount': FieldValue.increment(1),
        if (orderType == 'takeaway') 'takeawayCount': FieldValue.increment(1),
        if (orderType == 'delivery') 'deliveryCount': FieldValue.increment(1),
        
        // Revenue by Payment Mode
        if (paymentMode == 'Cash') 'cashCollection': FieldValue.increment(total),
        if (paymentMode == 'UPI') 'upiCollection': FieldValue.increment(total),
        if (paymentMode == 'Card') 'cardCollection': FieldValue.increment(total),
      }, SetOptions(merge: true));
      await batch.commit();

      final usb = context.read<UsbPrinterService>();
      final bt = context.read<BluetoothPrinterService>();
      final isAndroid = !kIsWeb && Platform.isAndroid;
      final dynamic printerService = isAndroid ? bt : usb;

      final billData = {
        'items': items, 'tableName': tableName, 'orderType': orderType, 'waiterName': 'POS',
        'status': 'completed', 'receiptNumber': receiptNo, 'billedAt': Timestamp.now(),
        'serviceCharge': serviceCharge, 'discount': discount, 'subtotal': subtotal,
        'gst': gst, 'cgst': gst / 2, 'sgst': gst / 2, 'gstPercentage': gstPercentage,
        'customerName': customerName,
        'customerContact': customerContact,
        'deliveryAddress': deliveryAddress,
        'restaurantId': restaurantId, // CRITICAL: Added for receipt metadata retrieval
      };

      // Smart Print (Thermal if configured, else PDF fallback)
      if (sharePdf) {
        await ReportService.shareBillAsPdf(
          orderData: billData,
          orderId: existingOrderId ?? "NEW",
          total: total,
          paymentMode: paymentMode,
          receiptNum: receiptNo.toString(),
        );
      } else {
        await ReportService.printFinalBill(
          orderData: billData,
          orderId: existingOrderId ?? '',
          subtotal: subtotal,
          total: total,
          paymentMode: paymentMode,
          hotelName: _restaurantName ?? auth.restaurantName ?? "YUG POS",
          address: _restaurantAddress ?? "",
          receiptNum: receiptNo.toString(),
          serviceCharge: serviceCharge,
          discount: discount,
          cgst: gst / 2,
          sgst: gst / 2,
          gstPercentage: gstPercentage,
          printerService: isAndroid ? bt : usb,
        );
      }
      
      if (mounted) {
        setState(() => _isProcessingBilling = false); // Successfully completed
        safePop(context);
        // Defer onComplete and snacking to avoid race conditions with navigation
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (onComplete != null) onComplete();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Billing Processed Successfully"), backgroundColor: V2Colors.green),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingBilling = false); // Ensure flag is reset on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Billing Error: $e"), backgroundColor: V2Colors.red),
        );
      }
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
      orderId: id,
      customerName: o['customerName'],
      customerContact: o['customerContact'],
      deliveryAddress: o['deliveryAddress'],
      onComplete: () => setState(() => _hFilter = 'billed'),
    );
  }

  DateTime _getDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  // --- MOBILE UI COMPONENTS ---

  Widget _buildMobileHeader(String? restaurantId, UserRole role) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: V2Colors.bg,
        border: Border(bottom: BorderSide(color: V2Colors.border, width: 0.5)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _restaurantName?.toUpperCase() ?? "YUG POS", 
                  style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.2)
                ),
                Text(
                  role == UserRole.waiter ? "WAITER" : (role == UserRole.cashier ? "CASHIER" : "ADMIN"), 
                  style: const TextStyle(color: V2Colors.muted, fontSize: 9, fontWeight: FontWeight.bold)
                ),
              ],
            ),
            Row(
              children: [
                if (role != UserRole.waiter)
                  StreamBuilder<DocumentSnapshot>(
                    stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
                    builder: (context, snapshot) {
                      double net = 0;
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        net = (data['netCollection'] ?? 0).toDouble();
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(8), border: Border.all(color: V2Colors.border)),
                        child: Column(
                          children: [
                            const Text("Net", style: TextStyle(color: V2Colors.muted, fontSize: 7, fontWeight: FontWeight.bold)),
                            Text("₹${net.toStringAsFixed(0)}", style: const TextStyle(color: V2Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(width: 12),
                Builder(
                  builder: (context) => InkWell(
                    onTap: () => Scaffold.of(context).openDrawer(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.menu, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileStatsCards(String? restaurantId) {
    if (_mobileActiveIndex != 1 && _mobileActiveIndex != 3) return const SizedBox.shrink();
    
    final auth = context.read<AuthService>();
    final isWaiter = auth.role == UserRole.waiter;
    
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    final cart = context.watch<CartProvider>();

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
      builder: (context, snapshot) {
        double dine = 0, tk = 0, del = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          dine = (data['tableCollection'] ?? 0).toDouble();
          tk = (data['takeawayCollection'] ?? 0).toDouble();
          del = (data['deliveryCollection'] ?? 0).toDouble();
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (!isWaiter) ...[
                _mobileStatCard("Dine in", "₹${dine.toInt()}", V2Colors.blue),
                _mobileStatCard("Takeaway", "₹${tk.toInt()}", V2Colors.orange),
                _mobileStatCard("Delivery", "₹${del.toInt()}", V2Colors.green),
              ],
              _mobileStatCard("Cart", "₹${cart.totalAmount.toInt()}", V2Colors.yellow),
            ],
          ),
        );
      },
    );
  }

  Widget _mobileStatCard(String label, String val, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: V2Colors.s2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: V2Colors.border, width: 0.5),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: V2Colors.muted, fontSize: 7, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(val, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    return SafeArea(
      child: Container(
        height: 68,
        decoration: const BoxDecoration(
          color: V2Colors.s1,
          border: Border(top: BorderSide(color: V2Colors.border, width: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (context.read<AuthService>().role != UserRole.waiter) _buildMobileNavIcon(0, Icons.home, "Home"),
            _buildMobileNavIcon(1, Icons.table_restaurant, "Tables"),
            _buildMobileCenterCartIcon(),
            if (context.read<AuthService>().role != UserRole.waiter) _buildMobileNavIcon(3, Icons.bar_chart, "Reports"),
            _buildMobileNavIcon(4, Icons.settings, "Settings"),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileNavIcon(int index, IconData icon, String label) {
    final isSel = _mobileActiveIndex == index;
    return InkWell(
      onTap: () => setState(() => _mobileActiveIndex = index),
      child: Container(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: isSel ? V2Colors.yellow : V2Colors.muted),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSel ? V2Colors.yellow : V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCenterCartIcon() {
    final cart = context.watch<CartProvider>();
    final isSel = _mobileActiveIndex == 2;
    return InkWell(
      onTap: () => setState(() => _mobileActiveIndex = 2),
      child: Transform.translate(
        offset: const Offset(0, -10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10), // Reduced from 12
                  decoration: BoxDecoration(
                    color: V2Colors.yellow,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: V2Colors.yellow.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)],
                  ),
                  child: const Icon(Icons.shopping_cart, size: 24, color: Colors.black),
                ),
                if (cart.items.isNotEmpty)
                  Positioned(
                    top: -2, right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      child: Text("${cart.totalItems}", style: const TextStyle(color: V2Colors.yellow, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2), // Reduced from 4
            Text("Cart", style: TextStyle(color: isSel ? V2Colors.yellow : V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileContentView(String? restaurantId, UserRole role) {
    switch (_mobileActiveIndex) {
      case 0: return _buildMobileHomeView(restaurantId, role);
      case 1: 
        final cart = context.watch<CartProvider>();
        if (cart.tableId != null || cart.orderType != OrderType.dineIn) {
          return _buildMobileOrderView(restaurantId, role);
        }
        return _buildMobileSelectionView(restaurantId, role);
      case 2: return _buildColumnCart(restaurantId, role, isMobile: true);
      case 3: return _buildMobileReportsView(restaurantId);
      case 4: return _buildMobileSettingsView();
      default: return const Center(child: Text("Home", style: TextStyle(color: V2Colors.muted)));
    }
  }

  Widget _buildMobileSelectionView(String? restaurantId, UserRole role) {
    final cart = context.watch<CartProvider>();
    return Column(
      children: [
        Container(
          height: 50,
          decoration: const BoxDecoration(color: V2Colors.s1, border: Border(bottom: BorderSide(color: V2Colors.border, width: 0.5))),
          child: Row(
            children: [
              _typeNavBtn("Dine In", OrderType.dineIn, Icons.restaurant),
              _typeNavBtn("Takeaway", OrderType.takeaway, Icons.takeout_dining),
              _typeNavBtn("Delivery", OrderType.delivery, Icons.delivery_dining),
            ],
          ),
        ),
        if (cart.orderType == OrderType.dineIn)
          Expanded(child: _buildColumnTables(restaurantId, role, isMobile: true))
        else
          Expanded(child: _buildMobileOrderView(restaurantId, role)),
      ],
    );
  }

  Widget _typeNavBtn(String label, OrderType type, IconData icon) {
    final cart = context.watch<CartProvider>();
    final isSel = cart.orderType == type;
    return Expanded(
      child: InkWell(
        onTap: () => cart.setOrderType(type),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSel ? V2Colors.yellow : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSel ? V2Colors.yellow : V2Colors.muted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: isSel ? V2Colors.yellow : V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileOrderView(String? restaurantId, UserRole role) {
    final cart = context.watch<CartProvider>();
    return Column(
      children: [
        if (cart.orderType == OrderType.dineIn)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: V2Colors.yellow.withOpacity(0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("TABLE: ${cart.tableName}", style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold, fontSize: 11)),
                InkWell(
                  onTap: () => cart.clearCart(),
                  child: const Text("CHANGE", style: TextStyle(color: V2Colors.muted, fontSize: 9, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        if (cart.orderType != OrderType.dineIn)
          _buildMobileCustomerForm(cart),
        Expanded(child: _buildColumnMenu(restaurantId, role)),
      ],
    );
  }

  Widget _buildMobileCustomerForm(CartProvider cart) {
    return Container(
      key: ValueKey("cust_form_${cart.orderType}"), // Force reset when order type changes
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(color: V2Colors.s1, border: Border(bottom: BorderSide(color: V2Colors.border))),
      child: Column(
        children: [
          _mobileInput("Customer name", (v) => cart.setCustomerName(v), initial: cart.customerName),
          const SizedBox(height: 8),
          _mobileInput("Contact number", (v) => cart.setCustomerContact(v), initial: cart.customerContact),
          if (cart.orderType == OrderType.delivery) ...[
            const SizedBox(height: 8),
            _mobileInput("Delivery address", (v) => cart.setDeliveryAddress(v), initial: cart.deliveryAddress),
          ],
        ],
      ),
    );
  }

  Widget _mobileInput(String hint, Function(String) onChange, {String? initial}) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(6), border: Border.all(color: V2Colors.border)),
      child: TextFormField(
        onChanged: onChange,
        initialValue: initial,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        decoration: InputDecoration(
          hintText: hint, 
          hintStyle: const TextStyle(color: V2Colors.muted, fontSize: 11), 
          border: InputBorder.none,
          contentPadding: const EdgeInsets.only(bottom: 12),
        ),
      ),
    );
  }

  Widget _buildMobileHomeView(String? restaurantId, UserRole role) {
    if (_showMobileHistoryList) {
      return Column(
        children: [
          Container(
            color: V2Colors.s1,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: V2Colors.yellow), onPressed: () => setState(() => _showMobileHistoryList = false)),
                const Text("Order History", style: TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Container(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _hChip("all", "All"),
                  _hChip("dineIn", "Dine In"),
                  _hChip("takeaway", "Takeaway"),
                  _hChip("delivery", "Delivery"),
                  _hFilterChip("billed", "Billed"),
                  _hFilterChip("active", "Pending"),
                ],
              ),
            ),
          ),
          Expanded(child: _buildHistoryList(restaurantId)),
        ],
      );
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$today";
    
    return Column(
      children: [
        // Date Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: V2Colors.s1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: V2Colors.yellow),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd/MM/yy').format(_selectedHistoryDate), 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                  ),
                ],
              ),
              InkWell(
                onTap: _selectHistoryDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(6)),
                  child: const Text("Filter Date", style: TextStyle(color: V2Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        
        // Summary Cards Section
        StreamBuilder<DocumentSnapshot>(
          stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
          builder: (context, snapshot) {
            double net = 0, dine = 0, tk = 0, del = 0;
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              net = (data['netCollection'] ?? 0).toDouble();
              dine = (data['tableCollection'] ?? 0).toDouble();
              tk = (data['takeawayCollection'] ?? 0).toDouble();
              del = (data['deliveryCollection'] ?? 0).toDouble();
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final cols = (constraints.maxWidth / 200).floor().clamp(2, 4);
                return Container(
                  padding: const EdgeInsets.all(12),
                  color: V2Colors.bg,
                  child: GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: cols == 2 ? 2.5 : 3.5, // Thinner cards
                    children: [
                      _hSummaryCard("Total Billed", "₹${net.toInt()}", V2Colors.yellow),
                      _hSummaryCard("Delivery", "₹${del.toInt()}", V2Colors.green),
                      _hSummaryCard("Dine in", "₹${dine.toInt()}", V2Colors.blue),
                      _hSummaryCard("Takeaway", "₹${tk.toInt()}", V2Colors.orange),
                    ],
                  ),
                );
              }
            );
          },
        ),
        // History Navigation Button
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ElevatedButton(
            onPressed: () {
               setState(() => _showMobileHistoryList = true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: V2Colors.yellow,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("View Order History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _hSummaryCard(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(10), border: Border.all(color: V2Colors.border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _hChip(String val, String label) {
    final isSel = _hTab == val;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      child: FilterChip(
        selected: isSel,
        label: Text(label, style: TextStyle(color: isSel ? Colors.black : V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold)),
        onSelected: (s) => setState(() => _hTab = val),
        backgroundColor: V2Colors.s3,
        selectedColor: V2Colors.yellow,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSel ? V2Colors.yellow : V2Colors.border)),
      ),
    );
  }

  Widget _hFilterChip(String val, String label) {
    final isSel = _hFilter == val;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      child: FilterChip(
        selected: isSel,
        label: Text(label, style: TextStyle(color: isSel ? Colors.black : V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold)),
        onSelected: (s) => setState(() => _hFilter = val),
        backgroundColor: V2Colors.s3,
        selectedColor: V2Colors.green,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSel ? V2Colors.green : V2Colors.border)),
      ),
    );
  }

  Widget _buildMobileSettingsView() {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final roleName = auth.role.toString().split('.').last.toUpperCase();

    return Container(
      color: V2Colors.s1,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [V2Colors.s2, V2Colors.s2.withOpacity(0.5)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: V2Colors.border, width: 0.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: V2Colors.yellow,
                    shape: BoxShape.circle,
                    border: Border.all(color: V2Colors.border, width: 4),
                  ),
                  child: Center(
                    child: Text(
                      (auth.userName ?? "U").substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(auth.userName ?? "Unknown User", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: V2Colors.yellow.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(roleName, style: const TextStyle(color: V2Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Details Section
          _settingsHeader("PERSONAL INFO"),
          _settingsRow(Icons.email_outlined, "Email", user?.email ?? "Not set"),
          _settingsRow(Icons.storefront_outlined, "Restaurant", auth.restaurantName ?? "Not set"),
          
          const SizedBox(height: 32),
          
          _settingsHeader("ACCOUNT"),
          _settingsActionRow(Icons.logout, "Logout", "Sign out from session", V2Colors.red, () => auth.logout()),
          
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                const Text("YUG POS v2.0.0", style: TextStyle(color: V2Colors.muted, fontSize: 10)),
                const SizedBox(height: 4),
                Text("RESTAURANT ID: ${auth.restaurantId ?? '-'}", style: const TextStyle(color: V2Colors.muted, fontSize: 8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(title, style: const TextStyle(color: V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _settingsRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(12), border: Border.all(color: V2Colors.border, width: 0.5)),
      child: Row(
        children: [
          Icon(icon, color: V2Colors.yellow, size: 20),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: V2Colors.muted, fontSize: 10)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsActionRow(IconData icon, String label, String sub, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(12), border: Border.all(color: V2Colors.border, width: 0.5)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(sub, style: const TextStyle(color: V2Colors.muted, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: V2Colors.muted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer() {
    final auth = context.read<AuthService>();
    return Drawer(
      backgroundColor: V2Colors.s1,
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
            color: V2Colors.s2,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 110,
                        height: 42,
                        child: Image.asset(
                          'assets/images/yug-poslogo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: V2Colors.muted, size: 20),
                      onPressed: () => Scaffold.of(context).closeDrawer(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: V2Colors.yellow,
                      child: Text((auth.userName ?? "U")[0], style: const TextStyle(color: Colors.black)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.userName ?? "User", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(auth.role.toString().split('.').last.toUpperCase(), style: const TextStyle(color: V2Colors.muted, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Drawer Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (widget.isAdminTab && widget.onTabSelect != null) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text("MAIN NAVIGATION", style: TextStyle(color: V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                  _drawerItem(Icons.dashboard_outlined, "Dashboard", () {
                    _scaffoldKey.currentState?.closeDrawer();
                    widget.onTabSelect!(0);
                  }),
                  _drawerItem(Icons.people_outline, "Staff Management", () {
                    _scaffoldKey.currentState?.closeDrawer();
                    widget.onTabSelect!(3);
                  }),
                  _drawerItem(Icons.restaurant_menu_outlined, "Menu Management", () {
                    _scaffoldKey.currentState?.closeDrawer();
                    widget.onTabSelect!(4);
                  }),
                  _drawerItem(Icons.analytics_outlined, "Analytics", () {
                    _scaffoldKey.currentState?.closeDrawer();
                    widget.onTabSelect!(2);
                  }),
                  const Divider(color: V2Colors.border, indent: 16, endIndent: 16),
                ],
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text("POS ACTIONS", style: TextStyle(color: V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
                _drawerItem(Icons.history_outlined, "Order History", () {
                  _scaffoldKey.currentState?.closeDrawer();
                  Navigator.push(context, MaterialPageRoute(builder: (context) => _buildFullHistoryPage(auth.restaurantId, auth.role)));
                }),
                _drawerItem(Icons.download_for_offline_outlined, "Download Daily Reports", () {
                  _scaffoldKey.currentState?.closeDrawer();
                  _showDownloadReportsDialog();
                }),
                _drawerItem(Icons.print_outlined, "Printer Settings", () {
                  _scaffoldKey.currentState?.closeDrawer();
                  _showPrinterSelectionDialog();
                }),
                _drawerItem(Icons.logout, "Logout Session", () {
                  _scaffoldKey.currentState?.closeDrawer();
                  auth.logout();
                }, color: V2Colors.red),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text("v1.0.0 Stable", style: TextStyle(color: V2Colors.muted, fontSize: 10)),
                Text("RES ID: ${auth.restaurantId?.substring(0, 8) ?? '...'}", style: const TextStyle(color: V2Colors.muted, fontSize: 8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? V2Colors.yellow, size: 20),
      title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showDownloadReportsDialog() async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;

    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: V2Colors.s2,
          title: const Text("Download Reports", style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select a date to download the daily collection summary.", style: TextStyle(color: V2Colors.muted, fontSize: 12)),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                    builder: (context, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(primary: V2Colors.yellow, onPrimary: Colors.black, surface: V2Colors.s2, onSurface: Colors.white),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setState(() => selectedDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(8), border: Border.all(color: V2Colors.border)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('dd-MM-yyyy').format(selectedDate), style: const TextStyle(color: Colors.white)),
                      const Icon(Icons.calendar_today, color: V2Colors.yellow, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => safePop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                safePop(context);
                final dateId = "${restaurantId}_${DateFormat('yyyy-MM-dd').format(selectedDate)}";
                final doc = await FirebaseFirestore.instance.collection('daily_collections').doc(dateId).get();
                
                if (!doc.exists) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No collections found for this date."), backgroundColor: V2Colors.red));
                  return;
                }

                final data = doc.data()!;
                await ReportService.printDailyCollection(
                  data: data,
                  restaurantName: auth.restaurantName ?? "YUG POS",
                  dateStr: DateFormat('dd-MM-yyyy').format(selectedDate),
                );
              },
              child: const Text("Download PDF Report"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportFilteredOrdersPDF() async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preparing Order List PDF..."), backgroundColor: V2Colors.yellow));

    final start = DateTime(_selectedHistoryDate.year, _selectedHistoryDate.month, _selectedHistoryDate.day);
    final end = start.add(const Duration(days: 1));

    try {
      Query q = _firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end));
      
      if (_hTab != 'all') q = q.where('orderType', isEqualTo: _hTab == 'table' ? 'dineIn' : _hTab);
      
      final snapshot = await q.orderBy('createdAt', descending: true).get();
      
      final orders = snapshot.docs.where((doc) {
        final o = doc.data() as Map<String, dynamic>;
        final status = o['status'] ?? 'new';
        if (_hFilter == 'active') {
          return status != 'billed' && status != 'done' && status != 'cleared' && status != 'cancelled';
        } else {
          return status == _hFilter;
        }
      }).map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        d['id'] = doc.id; // ensure ID is available
        return d;
      }).toList();

      if (orders.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No orders found for the current filters."), backgroundColor: V2Colors.orange));
        return;
      }

      await ReportService.printOrderHistoryList(
        orders: orders,
        restaurantName: auth.restaurantName ?? "YUG POS",
        date: _selectedHistoryDate,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: V2Colors.red));
    }
  }

  Widget _buildMobileReportsView(String? restaurantId) {
    final today = DateFormat('yyyy-MM-dd').format(_selectedReportsDate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Generate Reports", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Text("Review and archive daily business performance.", style: TextStyle(color: V2Colors.muted, fontSize: 11)),
          const SizedBox(height: 24),
          
          // Date Selector Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: V2Styles.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("SELECT DATE", style: TextStyle(color: V2Colors.muted, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedReportsDate,
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
                      builder: (context, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(primary: V2Colors.yellow, onPrimary: Colors.black, surface: V2Colors.s2, onSurface: Colors.white),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) setState(() => _selectedReportsDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: V2Colors.s3, borderRadius: BorderRadius.circular(8), border: Border.all(color: V2Colors.border)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat('EEEE, dd MMMM yyyy').format(_selectedReportsDate), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                        const Icon(Icons.calendar_month, color: V2Colors.yellow, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          // Report Actions
          _buildReportActionCard(
            title: "Daily Collection Summary",
            description: "A professional PDF with net revenue, payment breakdown, and source counts.",
            icon: Icons.assignment,
            onTap: () async {
              final auth = context.read<AuthService>();
              final dateId = "${restaurantId}_${DateFormat('yyyy-MM-dd').format(_selectedReportsDate)}";
              final doc = await _firestore.collection('daily_collections').doc(dateId).get();
              
              if (!doc.exists) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No records found for this date."), backgroundColor: V2Colors.orange));
                return;
              }
              
              await ReportService.printDailyCollection(
                data: doc.data()!,
                restaurantName: auth.restaurantName ?? "YUG POS",
                dateStr: DateFormat('dd-MM-yyyy').format(_selectedReportsDate),
              );
            },
          ),
          
          const SizedBox(height: 16),
          
          _buildReportActionCard(
            title: "Detailed Order List",
            description: "A granular list of all transactions for the day, including item summaries and token IDs.",
            icon: Icons.list_alt,
            onTap: () async {
              final auth = context.read<AuthService>();
              if (restaurantId == null) return;
              
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fetching order list..."), backgroundColor: V2Colors.yellow));
              
              final start = DateTime(_selectedReportsDate.year, _selectedReportsDate.month, _selectedReportsDate.day);
              final end = start.add(const Duration(days: 1));

              try {
                final snapshot = await _firestore.collection('orders')
                    .where('restaurantId', isEqualTo: restaurantId)
                    .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
                    .where('createdAt', isLessThan: Timestamp.fromDate(end))
                    .get();
                
                final orders = snapshot.docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  d['id'] = doc.id;
                  return d;
                }).toList();

                if (orders.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No orders found for this date."), backgroundColor: V2Colors.orange));
                  return;
                }

                await ReportService.printOrderHistoryList(
                  orders: orders,
                  restaurantName: auth.restaurantName ?? "YUG POS",
                  date: _selectedReportsDate,
                );
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: V2Colors.red));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReportActionCard({required String title, required String description, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: V2Styles.cardDecoration,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: V2Colors.yellow.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: V2Colors.yellow, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(color: V2Colors.muted, fontSize: 10, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: V2Colors.muted, size: 20),
          ],
        ),
      ),
    );
  }
  Widget _buildFullHistoryPage(String? restaurantId, UserRole role) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      appBar: AppBar(
        backgroundColor: V2Colors.s1,
        title: const Text("Order History", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => safePop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: V2Colors.yellow),
            onPressed: () => _exportFilteredOrdersPDF(),
            tooltip: "Download PDF Order List",
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _hChip("all", "All"),
                  _hChip("dineIn", "Dine In"),
                  _hChip("takeaway", "Takeaway"),
                  _hChip("delivery", "Delivery"),
                  _hFilterChip("billed", "Billed"),
                  _hFilterChip("active", "Pending"),
                ],
              ),
            ),
          ),
          Expanded(child: _buildHistoryList(restaurantId)),
        ],
      ),
    );
  }

  // --- RESPONSIVE LAYOUT (HIDDEN ON MOBILE NOW) ---
  Widget _buildResponsiveLayout(BuildContext context, String? restaurantId, UserRole role) => Container();
}

