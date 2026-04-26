import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:math';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../services/usb_printer_service.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../services/lan_printer_service.dart';
import '../../utils/navigator_utils.dart';

class RecentBillsScreen extends StatefulWidget {
  const RecentBillsScreen({super.key});

  @override
  State<RecentBillsScreen> createState() => _RecentBillsScreenState();
}

class _RecentBillsScreenState extends State<RecentBillsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Future<List<QueryDocumentSnapshot>> _fetchTodayBills(String? restaurantId) async {
    if (restaurantId == null) return [];

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    // Query 1: Last 50 bills by billedAt (Standard)
    final billedSnap = await _firestore
        .collection('orders')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('status', isEqualTo: 'billed')
        .orderBy('billedAt', descending: true)
        .limit(50)
        .get();

    // Query 2: Last 50 bills by completedAt (Alternative)
    final completedSnap = await _firestore
        .collection('orders')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .limit(50)
        .get();

    final Map<String, QueryDocumentSnapshot> merged = {};
    for (final d in billedSnap.docs) {
      merged[d.id] = d;
    }
    for (final d in completedSnap.docs) {
      merged.putIfAbsent(d.id, () => d);
    }
    
    // Fallback: If list is still small, add legacy or today's results that might be mismatching status
    if (merged.length < 10) {
       final createdSnap = await _firestore
          .collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThan: end)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
       for (final d in createdSnap.docs) {
         merged.putIfAbsent(d.id, () => d);
       }
    }

    final list = merged.values.toList();
    // Sort by most recent settlement time across all possible fields
    list.sort((a, b) {
      final ad = a.data() as Map<String, dynamic>;
      final bd = b.data() as Map<String, dynamic>;
      
      final aTs = (ad['billedAt'] as Timestamp?) ?? 
                  (ad['completedAt'] as Timestamp?) ?? 
                  (ad['createdAt'] as Timestamp?);
      final bTs = (bd['billedAt'] as Timestamp?) ?? 
                  (bd['completedAt'] as Timestamp?) ?? 
                  (bd['createdAt'] as Timestamp?);
                  
      final aDt = aTs?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDt = bTs?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDt.compareTo(aDt);
    });

    return list;
  }

  double _orderTotal(Map<String, dynamic> data) {
    final raw = data['totalAmount'] ?? data['grandTotal'] ?? data['subtotal'] ?? 0;
    return raw is num ? raw.toDouble() : double.tryParse(raw.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    final isWaiter = auth.role == UserRole.waiter;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141615),
        elevation: 0,
        title: const Text("RECENT BILLS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        actions: [
          if (!isWaiter)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent),
              onPressed: () => _downloadHistoryPdf(restaurantId),
              tooltip: "Download PDF History",
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isWaiter) _buildHeader(restaurantId),
          _buildSearchField(),
          Expanded(child: _buildBillsList()),
        ],
      ),
    );
  }

  Widget _buildHeader(String? restaurantId) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = _firestore.collection('daily_collections').doc("${restaurantId}_$today");

    // Windows workaround: avoid Firestore streams due to platform-thread violations
    // in older firebase plugins on Windows desktop.
    if (Platform.isWindows) {
      return FutureBuilder<DocumentSnapshot>(
        future: ref.get(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final totalBills = data?['billCount'] ?? 0;
          final netRevenue = max(0.0, (data?['netCollection'] ?? 0.0).toDouble());

          return Container(
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF141615),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem("TODAY'S BILLS", "$totalBills", Icons.receipt_long, const Color(0xFFFCDD22)),
                Container(width: 1, height: 40, color: Colors.white10),
                _buildStatItem("NET REVENUE", "₹${(netRevenue as num).toDouble().toStringAsFixed(0)}", Icons.payments, Colors.greenAccent),
              ],
            ),
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: ref.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final totalBills = data?['billCount'] ?? 0;
        final netRevenue = max(0.0, (data?['netCollection'] ?? 0.0).toDouble());

        return Container(
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF141615),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("TODAY'S BILLS", "$totalBills", Icons.receipt_long, const Color(0xFFFCDD22)),
              Container(width: 1, height: 40, color: Colors.white10),
              _buildStatItem("NET REVENUE", "₹${(netRevenue as num).toDouble().toStringAsFixed(0)}", Icons.payments, Colors.greenAccent),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color.withOpacity(0.7)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Search Bill # or Table Name...",
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Color(0xFFFCDD22), size: 20),
          filled: true,
          fillColor: const Color(0xFF141615),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildBillsList() {
    final restaurantId = context.read<AuthService>().restaurantId;

    // Windows plugin issue affects streams; we use Future fetch for all platforms
    // and rely on the refresh icon to re-fetch.
    return FutureBuilder<List<QueryDocumentSnapshot>>(
      future: _fetchTodayBills(restaurantId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)));

        final allOrders = snapshot.data ?? [];

        final filteredOrders = allOrders.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status != 'billed' && status != 'completed') return false;

          final receiptNum = data['receiptNumber']?.toString() ?? '';
          final tableName = data['tableName']?.toString().toLowerCase() ?? '';
          final billId = doc.id.toLowerCase();
          return receiptNum.contains(_searchQuery) || tableName.contains(_searchQuery) || billId.contains(_searchQuery);
        }).toList();

        if (filteredOrders.isEmpty) {
          return const Center(child: Text("No matching bills found", style: TextStyle(color: Colors.white38)));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filteredOrders.length,
          itemBuilder: (context, index) {
            final doc = filteredOrders[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildBillCard(doc.id, data);
          },
        );
      },
    );
  }

  /*
  // Old stream-based implementation kept for reference.
  Widget _buildBillsListStream() {
    // ...
  }
  */

  Widget _buildBillCard(String orderId, Map<String, dynamic> data) {
    final isWaiter = context.read<AuthService>().role == UserRole.waiter;
    final timestamp = (data['billedAt'] as Timestamp?)?.toDate() ?? 
                      (data['completedAt'] as Timestamp?)?.toDate() ?? 
                      (data['createdAt'] as Timestamp?)?.toDate() ?? 
                      DateTime.now();
    final total = _orderTotal(data);
    final receiptNum = data['receiptNumber'] ?? orderId.substring(orderId.length - 6).toUpperCase();
    final paymentMode = (data['paymentMode'] ?? data['paymentMethod'] ?? 'CASH').toString().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: InkWell(
        onTap: () => _showBillDetails(orderId, data),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long, color: Color(0xFFFCDD22), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("BILL #$receiptNum", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      "${data['tableName']} • ${DateFormat('hh:mm a').format(timestamp)}",
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(paymentMode, style: const TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.print, color: Colors.blueAccent, size: 20),
                onPressed: () => _reprintBill(orderId, data),
                tooltip: "Reprint Receipt",
              ),
              if (!isWaiter)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () => _confirmDeleteBill(orderId, data),
                  tooltip: "Delete Bill",
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBillDetails(String orderId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("BILL DETAILS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => safePop(context)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow("Table", data['tableName'] ?? 'N/A'),
                _buildDetailRow("Customer", data['customerName'] ?? 'Walk-in'),
                _buildDetailRow("Payment", (data['paymentMode'] ?? data['paymentMethod'] ?? 'CASH').toString().toUpperCase()),
                const Divider(color: Colors.white10, height: 24),
                const Text("ITEMS", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...(data['items'] as List).map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${item['quantity']}x ${item['name']}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text("₹${(item['price'] * item['quantity']).toStringAsFixed(0)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                )),
                const Divider(color: Colors.white10, height: 24),
                const Divider(color: Colors.white10, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("TOTAL AMOUNT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("₹${data['totalAmount']}", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.w900, fontSize: 20)),
                  ],
                ),
                if (context.read<AuthService>().role != UserRole.waiter) ...[
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        safePop(context);
                        _confirmDeleteBill(orderId, data);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.1),
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text("DELETE THIS BILL", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  void _confirmDeleteBill(String orderId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("DELETE BILL?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          "This will permanently delete the bill and subtract the amount from the daily revenue report. This action cannot be undone.",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              safePop(context);
              _deleteBill(orderId, data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("CONFIRM DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      
      // 1. Delete Order Document
      batch.delete(_firestore.collection('orders').doc(orderId));

      // 2. Adjust Revenue in Daily Collections
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

      // 3. Adjust Payment Method Totals
      final String paymentMode = (data['paymentMode'] ?? '').toString().toLowerCase();
      if (paymentMode == 'upi') {
        revUpdate['upiCollection'] = FieldValue.increment(-total);
      } else if (paymentMode == 'cash') {
        revUpdate['cashCollection'] = FieldValue.increment(-total);
      }

      batch.update(_firestore.collection('daily_collections').doc(collectionId), revUpdate);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bill deleted successfully. Daily totals updated."), backgroundColor: Colors.redAccent)
        );
        setState(() {}); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error deleting bill: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  void _reprintBill(String orderId, Map<String, dynamic> data) async {
    try {
      final auth = context.read<AuthService>();
      await ReportService.printFinalBill(
        data: data,
        orderId: orderId,
        total: (data['totalAmount'] as num).toDouble(),
        paymentMode: data['paymentMode'] ?? 'Cash',
        bt: context.read<BluetoothPrinterService>(),
        usb: context.read<UsbPrinterService>(),
        lan: context.read<LanPrinterService>(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reprinting Bill..."), backgroundColor: Colors.blueAccent));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _downloadHistoryPdf(String? restaurantId) async {
    if (restaurantId == null) return;
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Generating Bill History PDF..."), duration: Duration(seconds: 2))
      );
    }

    try {
      final allOrdersDocs = await _fetchTodayBills(restaurantId);
      
      // Filter orders to match what's currently shown on screen (search query included)
      final filtered = allOrdersDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status != 'billed' && status != 'completed') return false;

        final receiptNum = data['receiptNumber']?.toString() ?? '';
        final tableName = data['tableName']?.toString().toLowerCase() ?? '';
        final billId = doc.id.toLowerCase();
        return receiptNum.contains(_searchQuery) || tableName.contains(_searchQuery) || billId.contains(_searchQuery);
      }).toList();

      if (filtered.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No orders found to export."), backgroundColor: Colors.orange));
        return;
      }

      // Convert to List of Maps for the ReportService
      final ordersData = filtered.map((doc) {
        final d = Map<String, dynamic>.from(doc.data() as Map);
        d['id'] = doc.id;
        return d;
      }).toList();

      final auth = context.read<AuthService>();
      
      // Calculate start/end dates from the list for the report header
      DateTime start = DateTime.now();
      DateTime end = DateTime.now();
      
      if (ordersData.isNotEmpty) {
        final sorted = List<Map<String, dynamic>>.from(ordersData);
        sorted.sort((a,b) {
          final da = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final db = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return da.compareTo(db);
        });
        start = (sorted.first['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        end = (sorted.last['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      }

      await ReportService.printOrderHistoryReport(
        restaurantName: auth.restaurantName ?? "YUG POS",
        orders: ordersData,
        startDate: start,
        endDate: end,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export Failed: $e"), backgroundColor: Colors.red));
      }
    }
  }
}
