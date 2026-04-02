import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141615),
        elevation: 0,
        title: const Text("RECENT BILLS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(restaurantId),
          _buildSearchField(),
          Expanded(child: _buildBillsList()),
        ],
      ),
    );
  }

  Widget _buildHeader(String? restaurantId) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('daily_collections').doc("${restaurantId}_$today").snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final totalBills = data?['billCount'] ?? 0;
        final netRevenue = data?['netCollection'] ?? 0.0;

        return Container(
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF141615),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("TODAY'S BILLS", "$totalBills", Icons.receipt_long, const Color(0xFFFCDD22)),
              Container(width: 1, height: 40, color: Colors.white10),
              _buildStatItem("NET REVENUE", "₹${netRevenue.toStringAsFixed(0)}", Icons.payments, Colors.greenAccent),
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
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('orders')
          .where('status', whereIn: ['completed', 'billed']) // Include both statuses
          .orderBy('billedAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)));

        final allOrders = snapshot.data?.docs ?? [];
        
        // Debugging for index/query issues
        if (allOrders.isEmpty && !snapshot.hasError && snapshot.connectionState == ConnectionState.active) {
            // If the header shows bills but we have 0, there might be a property mismatch
        }

        final filteredOrders = allOrders.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // "Recent Bills" is meant to show today's billed orders.
          final billedAtTs = data['billedAt'] as Timestamp?;
          if (billedAtTs == null) return false;
          final billedAt = billedAtTs.toDate();
          final isToday = billedAt.year == todayMidnight.year && billedAt.month == todayMidnight.month && billedAt.day == todayMidnight.day;
          if (!isToday) return false;

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

  Widget _buildBillCard(String orderId, Map<String, dynamic> data) {
    final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final total = (data['totalAmount'] as num).toDouble();
    final receiptNum = data['receiptNumber'] ?? orderId.substring(orderId.length - 6).toUpperCase();
    final paymentMode = data['paymentMode']?.toString().toUpperCase() ?? 'CASH';

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
            IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
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
                _buildDetailRow("Payment", data['paymentMode']?.toString().toUpperCase() ?? 'CASH'),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("TOTAL AMOUNT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("₹${data['totalAmount']}", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.w900, fontSize: 20)),
                  ],
                ),
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

  void _reprintBill(String orderId, Map<String, dynamic> data) async {
    try {
      final auth = context.read<AuthService>();
      await ReportService.printFinalBill(
        orderData: data,
        orderId: orderId,
        subtotal: (data['totalAmount'] as num).toDouble(),
        cgst: 0, sgst: 0,
        total: (data['totalAmount'] as num).toDouble(),
        paymentMode: data['paymentMode'] ?? 'Cash',
        hotelName: auth.restaurantName ?? "YUG POS",
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
}
