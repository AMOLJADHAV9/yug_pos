import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import './v2_styles.dart';
import '../../utils/navigator_utils.dart';

class CashierReportsScreen extends StatefulWidget {
  const CashierReportsScreen({super.key});

  @override
  State<CashierReportsScreen> createState() => _CashierReportsScreenState();
}

class _CashierReportsScreenState extends State<CashierReportsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _orderTypeFilter = 'ALL'; // ALL, DINEIN, TAKEAWAY, DELIVERY
  String _statusFilter = 'BILLED'; // BILLED, PENDING, CANCELLED
  bool _isLoading = false;

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
              primary: V2Colors.yellow,
              onPrimary: V2Colors.bg,
              surface: V2Colors.s1,
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

  Future<void> _downloadDailyReport(String restaurantId, String hotelName) async {
    setState(() => _isLoading = true);
    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = DateTime(today.year, today.month, today.day, 23, 59, 59);

      final snapshot = await _firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('billedAt', isGreaterThanOrEqualTo: start)
          .where('billedAt', isLessThanOrEqualTo: end)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No billed orders for today yet.")));
        return;
      }

      await ReportService.generatePeriodReport(
        "Daily Sales Report", 
        "Date: ${DateFormat('dd MMM yyyy').format(today)}", 
        snapshot.docs, 
        restaurantName: hotelName
      );
    } catch (e) {
      debugPrint("Report Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printFilteredHistory(String restaurantId, String hotelName) async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _buildQuery(restaurantId).get();
      if (snapshot.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No records found for the current filters.")));
        return;
      }

      final orders = snapshot.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
      }).toList();

      await ReportService.printOrderHistoryReport(
        restaurantName: hotelName,
        orders: orders,
        startDate: _startDate,
        endDate: _endDate,
      );
    } catch (e) {
      debugPrint("Print Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                if (createdAt != null) Text("Placed at ${DateFormat('dd MMM, hh:mm a').format(createdAt)}", style: const TextStyle(color: V2Colors.muted, fontSize: 10)),
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
              if (type.toString().toLowerCase() == 'takeaway' || type.toString().toLowerCase() == 'delivery') ...[
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
                      Text(cName ?? (type.toString().toLowerCase() == 'delivery' ? 'Delivery Customer' : 'takeaway'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      if (cContact != null && cContact.toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text("📞 $cContact", style: const TextStyle(color: V2Colors.yellow, fontSize: 12)),
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
                  itemBuilder: (context, idx) {
                    final item = items[idx];
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(4)),
                          child: Text("${item['quantity']}x", style: const TextStyle(color: V2Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(item['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12))),
                        Text("₹${(item['price'] * item['quantity']).toStringAsFixed(0)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: V2Colors.yellow, thickness: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOTAL AMOUNT", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: V2Colors.yellow, fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;
    final hotelName = auth.restaurantName ?? "YUG POS";

    return Scaffold(
      backgroundColor: V2Colors.bg,
      appBar: AppBar(
        title: const Text("REPORTS & HISTORY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isLoading ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: V2Colors.yellow)) : const Icon(Icons.download, color: V2Colors.yellow),
            onPressed: (restaurantId == null || _isLoading) ? null : () => _downloadDailyReport(restaurantId, hotelName),
            tooltip: "Download Today's Report",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: restaurantId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderActions(restaurantId, hotelName),
                _buildFilters(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _buildQuery(restaurantId).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return const Center(child: Text("No records match these filters.", style: TextStyle(color: V2Colors.muted)));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          return _buildOrderCard(data, docs[index].id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderActions(String restaurantId, String hotelName) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _selectDateRange(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: V2Colors.s1, borderRadius: BorderRadius.circular(8), border: Border.all(color: V2Colors.border)),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: V2Colors.yellow),
                    const SizedBox(width: 12),
                    Text(
                      "${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}",
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildActionButton(Icons.print_outlined, "Print List", _isLoading ? null : () => _printFilteredHistory(restaurantId, hotelName))
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          _buildChipGroup("Type", ['ALL', 'DINEIN', 'TAKEAWAY', 'DELIVERY'], _orderTypeFilter, (v) => setState(() => _orderTypeFilter = v)),
          const SizedBox(width: 16),
          _buildChipGroup("Status", ['BILLED', 'PENDING', 'CANCELLED'], _statusFilter, (v) => setState(() => _statusFilter = v)),
        ],
      ),
    );
  }

  Widget _buildChipGroup(String label, List<String> options, String current, Function(String) onSelect) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$label: ", style: const TextStyle(color: V2Colors.muted, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        ...options.map((opt) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(opt, style: const TextStyle(fontSize: 10)),
            selected: current == opt,
            onSelected: (s) => onSelect(opt),
            backgroundColor: V2Colors.s1,
            selectedColor: V2Colors.yellow.withOpacity(0.2),
            labelStyle: TextStyle(color: current == opt ? V2Colors.yellow : V2Colors.muted, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: current == opt ? V2Colors.yellow.withOpacity(0.5) : V2Colors.border)),
          ),
        )).toList(),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> data, String id) {
    final date = (data['billedAt'] as Timestamp?)?.toDate() ?? (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final type = (data['orderType'] ?? 'dineIn').toString().toUpperCase();
    final total = (data['totalAmount'] ?? 0).toDouble();

    return InkWell(
      onTap: () => _showOrderDetailDialog(id, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: V2Colors.s1, borderRadius: BorderRadius.circular(8), border: Border.all(color: V2Colors.border)),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: V2Colors.s2, borderRadius: BorderRadius.circular(8)),
              child: Icon(_getIconForType(type), size: 18, color: V2Colors.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Bill #${data['receiptNumber'] ?? id.substring(id.length-4).toUpperCase()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: V2Colors.yellow, fontWeight: FontWeight.w900, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${DateFormat('dd MMM, hh:mm a').format(date)} • $type", style: const TextStyle(color: V2Colors.muted, fontSize: 10)),
                      _statusBadge(data['status'] ?? 'pending'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color c = Colors.orange;
    if (status == 'billed') c = V2Colors.green;
    if (status == 'cancelled') c = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }

  IconData _getIconForType(String type) {
    if (type.contains('TAKEAWAY')) return Icons.shopping_bag_outlined;
    if (type.contains('DELIVERY')) return Icons.delivery_dining_outlined;
    return Icons.restaurant_outlined;
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: V2Colors.yellow,
        foregroundColor: V2Colors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Query _buildQuery(String restaurantId) {
    Query query = _firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId);

    // Date range
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final end = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    if (_statusFilter == 'BILLED') {
      query = query.where('status', isEqualTo: 'billed')
                   .where('billedAt', isGreaterThanOrEqualTo: start)
                   .where('billedAt', isLessThanOrEqualTo: end);
    } else {
      query = query.where('status', isEqualTo: _statusFilter.toLowerCase())
                   .where('createdAt', isGreaterThanOrEqualTo: start)
                   .where('createdAt', isLessThanOrEqualTo: end);
    }

    if (_orderTypeFilter != 'ALL') {
      String firestoreType = _orderTypeFilter.toLowerCase();
      if (_orderTypeFilter == 'DINEIN') firestoreType = 'dineIn';
      query = query.where('orderType', isEqualTo: firestoreType);
    }

    return query.orderBy(_statusFilter == 'BILLED' ? 'billedAt' : 'createdAt', descending: true);
  }
}
