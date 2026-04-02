import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _isPrinting = false;
  String _statusFilter = 'ALL';

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFCDD22),
              onPrimary: const Color(0xFF141615),
              surface: Color(0xFF141615),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;

    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      appBar: AppBar(
        title: const Text("ORDER HISTORY REPORT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF141615),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Color(0xFFFCDD22)),
            onPressed: () => _selectDateRange(context),
            tooltip: "Filter by Date Range",
          ),
        ],
      ),
      body: restaurantId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterSummary(),
                _buildStatusFilter(), // Add status chips
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _buildOrdersQuery(restaurantId).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        debugPrint("Orders Error: ${snapshot.error}");
                        return Center(child: Text("Error loading orders: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(child: Text("No orders found for this period", style: TextStyle(color: Colors.grey)));
                      }

                      double totalRevenue = 0;
                      for (var doc in docs) {
                        totalRevenue += (doc.data() as Map<String, dynamic>)['totalAmount'] ?? 0;
                      }

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            color: const Color(0xFF141615),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("${docs.length} ORDERS FOUND", style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                                Text("TOTAL: ₹${totalRevenue.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                                final status = data['status']?.toString().toUpperCase() ?? 'N/A';
                                
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141615),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          data['receiptNumber'] != null 
                                          ? "Bill #${data['receiptNumber']}" 
                                          : "Order #${doc.id.substring(doc.id.length - 6).toUpperCase()}", 
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                                        ),
                                        Text("₹${data['totalAmount'] ?? '0'}", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.w900, fontSize: 14)),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(DateFormat('dd MMM, hh:mm a').format(createdAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                            _statusChip(status, data['paymentMode']?.toString()),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text("${data['orderType']?.toString().toUpperCase()} | ${data['customerName'] ?? 'Walk-in'}", style: const TextStyle(color: Colors.white60, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          _buildPrintButton(auth.restaurantName ?? "YUG POS", docs),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCDD22).withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.date_range, color: Colors.white38, size: 16),
          const SizedBox(width: 8),
          Text(
            "${DateFormat('dd/MM/yy').format(_startDate)}  to  ${DateFormat('dd/MM/yy').format(_endDate)}",
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String s, [String? paymentMode]) {
    Color c = Colors.grey;
    bool isPaid = s == 'BILLED' || s == 'PAID' || s == 'COMPLETED';
    if (isPaid) c = Colors.green;
    else if (s == 'CANCELLED') c = Colors.red;
    else if (s == 'ACTIVE' || s == 'OCCUPIED' || s == 'PENDING') c = Colors.orange;

    String displayText = (isPaid && paymentMode != null && paymentMode.isNotEmpty) ? "PAID (${paymentMode.toUpperCase()})" : s;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: c.withOpacity(0.3))),
      child: Text(displayText, style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatusFilter() {
    final statuses = ['ALL', 'COMPLETED', 'BILLED', 'PENDING', 'CANCELLED'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: statuses.map((s) {
            final isSelected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF141615) : Colors.white70)),
                selected: isSelected,
                onSelected: (val) => setState(() => _statusFilter = s),
                backgroundColor: Colors.white.withOpacity(0.05),
                selectedColor: const Color(0xFFFCDD22),
                checkmarkColor: const Color(0xFF141615),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Query _buildOrdersQuery(String restaurantId) {
    Query query = _firestore.collection('orders')
        .where('restaurantId', isEqualTo: restaurantId);

    // Filter by appropriate date field based on status
    final dateField = (_statusFilter == 'COMPLETED') ? 'billedAt' : 'createdAt';
    
    query = query.where(dateField, isGreaterThanOrEqualTo: DateTime(_startDate.year, _startDate.month, _startDate.day))
                 .where(dateField, isLessThanOrEqualTo: DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59));

    if (_statusFilter == 'COMPLETED') {
      query = query.where('status', whereIn: ['completed', 'billed']);
    } else if (_statusFilter != 'ALL') {
      query = query.where('status', isEqualTo: _statusFilter.toLowerCase());
    }

    return query.orderBy(dateField, descending: true);

    return query.orderBy(dateField, descending: true);
  }

  Widget _buildPrintButton(String hotelName, List<QueryDocumentSnapshot> docs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        boxShadow: [BoxShadow(color: const Color(0xFF141615).withOpacity(0.5), blurRadius: 10)],
      ),
      child: ElevatedButton.icon(
        icon: _isPrinting ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF141615))) : const Icon(Icons.print),
        label: const Text("PRINT FULL HISTORY REPORT", style: TextStyle(fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFCDD22),
          foregroundColor: const Color(0xFF141615),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _isPrinting ? null : () async {
          setState(() => _isPrinting = true);
          try {
            final List<Map<String, dynamic>> ordersList = docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              data['id'] = d.id;
              return data;
            }).toList();
            await ReportService.printOrderHistoryReport(
              restaurantName: hotelName,
              orders: ordersList,
              startDate: _startDate,
              endDate: _endDate,
            );
          } catch (e) {
            debugPrint("Print Error: $e");
          } finally {
            if (mounted) setState(() => _isPrinting = false);
          }
        },
      ),
    );
  }
}
