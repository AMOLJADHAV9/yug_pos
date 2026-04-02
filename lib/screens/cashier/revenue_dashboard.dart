import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';

class RevenueDashboard extends StatefulWidget {
  const RevenueDashboard({super.key});

  @override
  State<RevenueDashboard> createState() => _RevenueDashboardState();
}

class _RevenueDashboardState extends State<RevenueDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, String> _itemCategoryMap = {};
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadItemCategories();
  }

  Future<void> _loadItemCategories() async {
    final auth = context.read<AuthService>();
    if (auth.restaurantId == null) return;

    final snapshot = await _firestore.collection('menu_items')
        .where('restaurantId', isEqualTo: auth.restaurantId)
        .get();
    
    final Map<String, String> tempMap = {};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final name = data['name']?.toString() ?? '';
      final category = data['category']?.toString() ?? 'Others';
      if (name.isNotEmpty) tempMap[name] = category;
    }

    if (mounted) {
      setState(() {
        _itemCategoryMap = tempMap;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docId = "${restaurantId}_$todayStr";
    final startOfToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      appBar: AppBar(
        title: const Text("REVENUE ANALYTICS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF141615),
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_isExporting)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFCDD22))))
          else
            IconButton(
              icon: const Icon(Icons.download_for_offline, color: Color(0xFFFCDD22)),
              onPressed: () => _handleExport(auth.restaurantName ?? "YUG POS", restaurantId, docId, startOfToday),
              tooltip: "Download PDF Report",
            ),
        ],
      ),
      body: restaurantId == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)))
          : StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('daily_collections').doc(docId).snapshots(),
              builder: (context, colSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('orders')
                      .where('restaurantId', isEqualTo: restaurantId)
                      .orderBy('createdAt', descending: true)
                      .limit(200)
                      .snapshots(),
                  builder: (context, orderSnap) {
                    if (colSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                    double net = 0, table = 0, takeaway = 0, delivery = 0;
                    int billCount = 0;

                    if (colSnap.hasData && colSnap.data!.exists) {
                      final data = colSnap.data!.data() as Map<String, dynamic>;
                      net = (data['netCollection'] ?? 0).toDouble();
                      table = (data['tableCollection'] ?? 0).toDouble();
                      takeaway = (data['takeawayCollection'] ?? 0).toDouble();
                      delivery = (data['deliveryCollection'] ?? 0).toDouble();
                      billCount = (data['billCount'] ?? 0).toInt();
                    }

                    int pending = 0, billed = 0, cancelled = 0;
                    Map<String, double> categorySales = {};

                    if (orderSnap.hasData) {
                      for (var doc in orderSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final status = data['status']?.toString().toLowerCase() ?? '';
                        final items = data['items'] as List<dynamic>? ?? [];
                        
                        final tsBilled = data['billedAt'] as Timestamp?;
                        final tsCreated = data['createdAt'] as Timestamp?;
                        
                        final isBilledToday = tsBilled != null && tsBilled.toDate().isAfter(startOfToday);
                        final isCreatedToday = tsCreated != null && tsCreated.toDate().isAfter(startOfToday);
                        final isPending = status == 'active' || status == 'occupied' || status == 'bill_requested' || status == 'open' || status == 'kotSent' || status == 'preparing';

                        if (isPending) {
                          pending++;
                        } else if (isBilledToday) {
                          billed++;
                        } else if (status == 'cancelled' && isCreatedToday) {
                          cancelled++;
                        }

                        // Only count revenue for orders billed today
                        if (isBilledToday && status != 'cancelled') {
                          for (var item in items) {
                            final name = item['name']?.toString() ?? '';
                            final qty = (item['quantity'] ?? 0).toDouble();
                            final price = (item['price'] ?? 0).toDouble();
                            final category = _itemCategoryMap[name] ?? 'Others';
                            categorySales[category] = (categorySales[category] ?? 0) + (qty * price);
                          }
                        }
                      }
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPremiumHeader(net, billCount),
                          const SizedBox(height: 16),
                          _buildStatusCards(pending, billed, cancelled),
                          const SizedBox(height: 24),
                          _buildRevenueSection(table, takeaway, delivery),
                          const SizedBox(height: 24),
                          if (categorySales.isNotEmpty) _buildCategoryAnalytics(categorySales),
                          const SizedBox(height: 24),
                          _buildPerformanceGraph(pending, billed, cancelled),
                          const SizedBox(height: 40),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildPremiumHeader(double net, int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFFCDD22).withOpacity(0.2), const Color(0xFF141615)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFCDD22).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("TODAY'S REVENUE", style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("₹${net.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 38, fontWeight: FontWeight.w900)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                child: Text("$count BILLS", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards(int pending, int billed, int cancelled) {
    return Row(
      children: [
        _buildMiniCard("PENDING", "$pending", Colors.orange),
        const SizedBox(width: 10),
        _buildMiniCard("BILLED", "$billed", Colors.blue),
        const SizedBox(width: 10),
        _buildMiniCard("CANCELLED", "$cancelled", Colors.red),
      ],
    );
  }

  Widget _buildMiniCard(String title, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF141615), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.1))),
        child: Column(
          children: [
            Text(title, style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(val, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueSection(double table, double takeaway, double delivery) {
    final total = table + takeaway + delivery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("SOURCE DISTRIBUTION", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF141615), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              SizedBox(
                width: 120, height: 120,
                child: total == 0 ? const Center(child: Icon(Icons.pie_chart, color: Colors.white10)) : PieChart(
                  PieChartData(sectionsSpace: 2, centerSpaceRadius: 30, sections: [
                    PieChartSectionData(color: const Color(0xFFFCDD22), value: table, title: '', radius: 20),
                    PieChartSectionData(color: Colors.purpleAccent, value: takeaway, title: '', radius: 20),
                    PieChartSectionData(color: Colors.deepOrange, value: delivery, title: '', radius: 20),
                  ]),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    _legendItem("Dine-In", table, const Color(0xFFFCDD22), total),
                    _legendItem("Takeaway", takeaway, Colors.purpleAccent, total),
                    _legendItem("Delivery", delivery, Colors.deepOrange, total),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryAnalytics(Map<String, double> categories) {
    final sorted = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = categories.values.fold(0.0, (sum, v) => sum + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("CATEGORY WISE SALES", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 16),
        ...sorted.take(5).map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                  Text("₹${e.value.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: e.value / total,
                backgroundColor: Colors.white.withOpacity(0.05),
                color: const Color(0xFFFCDD22).withOpacity(0.8),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildPerformanceGraph(int pending, int billed, int cancelled) {
    final maxVal = [pending, billed, cancelled].reduce((a, b) => a > b ? a : b).toDouble() + 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("ORDER PERFORMANCE", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 16),
        Container(
          height: 180,
          padding: const EdgeInsets.fromLTRB(10, 20, 10, 0),
          decoration: BoxDecoration(color: const Color(0xFF141615), borderRadius: BorderRadius.circular(16)),
          child: BarChart(
            BarChartData(
              maxY: maxVal,
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                  if (v == 0) return _barLabel("P");
                  if (v == 1) return _barLabel("B");
                  if (v == 2) return _barLabel("C");
                  return const SizedBox.shrink();
                })),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                _barGrp(0, pending.toDouble(), Colors.orange),
                _barGrp(1, billed.toDouble(), Colors.blue),
                _barGrp(2, cancelled.toDouble(), Colors.red),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _barLabel(String l) => Padding(padding: const EdgeInsets.only(top: 8), child: Text(l, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)));

  BarChartGroupData _barGrp(int x, double y, Color c) => BarChartGroupData(x: x, barRods: [BarChartRodData(toY: y, color: c, width: 20, borderRadius: BorderRadius.circular(4))]);

  Widget _legendItem(String l, double v, Color c, double t) {
    final p = t > 0 ? (v / t * 100).toStringAsFixed(0) : "0";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(l, style: const TextStyle(color: Colors.white60, fontSize: 11))),
          Text("₹${v.toStringAsFixed(0)} ($p%)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _handleExport(String hotelName, String? restaurantId, String docId, DateTime startOfToday) async {
    if (restaurantId == null) return;
    setState(() => _isExporting = true);
    try {
      final colDoc = await _firestore.collection('daily_collections').doc(docId).get();
      final orderSnap = await _firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .get();

      double net = 0, table = 0, takeaway = 0, delivery = 0;
      int billCount = 0;
      if (colDoc.exists) {
        final data = colDoc.data()!;
        net = (data['netCollection'] ?? 0).toDouble();
        table = (data['tableCollection'] ?? 0).toDouble();
        takeaway = (data['takeawayCollection'] ?? 0).toDouble();
        delivery = (data['deliveryCollection'] ?? 0).toDouble();
        billCount = (data['billCount'] ?? 0).toInt();
      }

      int pending = 0, billed = 0, cancelled = 0;
      Map<String, double> categorySales = {};
      final validDocs = orderSnap.docs.where((doc) {
        final data = doc.data();
        final ts = data['billedAt'] as Timestamp?;
        if (ts == null) return false; // Export only billed orders for revenue report
        return ts.toDate().isAfter(startOfToday) || ts.toDate().isAtSameMomentAs(startOfToday);
      }).toList();

      for (var doc in validDocs) {
        final data = doc.data();
        final status = data['status']?.toString().toLowerCase() ?? '';
        final items = data['items'] as List<dynamic>? ?? [];
        if (status == 'active' || status == 'occupied' || status == 'bill_requested') pending++;
        else if (status == 'billed' || status == 'completed' || status == 'paid') billed++;
        else if (status == 'cancelled') cancelled++;
        if (status != 'cancelled') {
          for (var item in items) {
            final name = item['name']?.toString() ?? '';
            final qty = (item['quantity'] ?? 0).toDouble();
            final price = (item['price'] ?? 0).toDouble();
            final cat = _itemCategoryMap[name] ?? 'Others';
            categorySales[cat] = (categorySales[cat] ?? 0) + (qty * price);
          }
        }
      }

      await ReportService.printSummaryReport(
        restaurantName: hotelName,
        netRevenue: net,
        billCount: billCount,
        revenueBySource: {"Dine-In": table, "Takeaway": takeaway, "Delivery": delivery},
        orderStatuses: {"Pending": pending, "Billed": billed, "Cancelled": cancelled},
        categories: categorySales,
      );
    } catch (e) {
      debugPrint("Export Error: $e");
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
