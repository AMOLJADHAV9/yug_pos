import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../services/report_service.dart';
import '../../../services/auth_service.dart';
import 'package:provider/provider.dart';

class RevenueTab extends StatefulWidget {
  const RevenueTab({super.key});

  @override
  State<RevenueTab> createState() => _RevenueTabState();
}

class _RevenueTabState extends State<RevenueTab> {
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final restaurantId = auth.restaurantId;

    if (restaurantId == null) {
      return const Scaffold(body: Center(child: Text("Restaurant context missing. Please login again.")));
    }

    final firestore = FirebaseFirestore.instance;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfYesterday = DateTime(yesterday.year, yesterday.month, yesterday.day);
    final startOfYear = DateTime(today.year, 1, 1);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Administration Overview", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          // ── TODAY ──────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildSectionHeader("Today's Performance", Icons.today, Colors.orange)),
                const SizedBox(width: 16),
                Text(DateFormat('dd MMM yyyy').format(DateTime.now()), 
                  style: const TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.bold)
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Use the single source of truth: daily_collections
            StreamBuilder<DocumentSnapshot>(
              stream: firestore.collection('daily_collections').doc("${restaurantId}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}").snapshots(),
              builder: (context, snapshot) {
                double todayRevenue = 0;
                double todayTableRevenue = 0;
                double todayTakeawayRevenue = 0;
                double todayOnlineRevenue = 0;
                int billCount = 0;
                int takeawayCount = 0;
                int tableCount = 0;
                int onlineCount = 0;

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  todayRevenue = (data['netCollection'] ?? 0).toDouble();
                  todayTableRevenue = (data['tableCollection'] ?? 0).toDouble();
                  todayTakeawayRevenue = (data['takeawayCollection'] ?? 0).toDouble();
                  todayOnlineRevenue = (data['onlineCollection'] ?? 0).toDouble();
                  billCount = data['billCount'] ?? 0;
                  takeawayCount = data['takeawayCount'] ?? 0;
                  tableCount = data['tableCount'] ?? 0;
                  onlineCount = data['onlineCount'] ?? 0;
                }

                final width = MediaQuery.of(context).size.width;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: width > 900 ? 5 : (width > 600 ? 5 : 2), 
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: width > 600 ? 1.0 : 1.1,
                  children: [
                    _buildStatCard(
                      "Daily Total", 
                      "₹${todayRevenue.toStringAsFixed(0)}", 
                      Icons.currency_rupee, 
                      Colors.green,
                      subtitle: "Total ($billCount Bills)",
                    ),
                    _buildStatCard(
                      "Table Sales", 
                      "₹${todayTableRevenue.toStringAsFixed(0)}", 
                      Icons.restaurant, 
                      const Color(0xFFE7FF12),
                      subtitle: "$tableCount Orders",
                    ),
                    _buildStatCard(
                      "Takeaway Sales", 
                      "₹${todayTakeawayRevenue.toStringAsFixed(0)}", 
                      Icons.shopping_bag, 
                      Colors.purpleAccent,
                      subtitle: "$takeawayCount Orders",
                    ),
                    _buildStatCard(
                      "Online Sales", 
                      "₹${todayOnlineRevenue.toStringAsFixed(0)}", 
                      Icons.cloud_download, 
                      Colors.blueAccent,
                      subtitle: "$onlineCount Z/S Orders",
                    ),
                    _buildActiveTablesCard(firestore, restaurantId),
                    _buildPendingKotsCard(firestore, restaurantId),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Diagnostic Label
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text("Data Source: $restaurantId • Live Sync Active", 
                style: const TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildSectionHeader("Revenue Trend", Icons.bar_chart, Colors.blue)),
              ],
            ),
            _buildMonthlyBarChart(firestore, startOfYear, restaurantId),
          ],
        ),
      );
    }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE7FF12).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFFE7FF12), size: 18),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFE7FF12).withOpacity(0.2), thickness: 1.5)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? subtitle, Color? subtitleColor}) {
    final themeYellow = const Color(0xFFE7FF12);
    return Container(
      height: 100, // Fixed height
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeYellow.withOpacity(0.05), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: themeYellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: subtitleColor ?? themeYellow, size: 12),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title,
                style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: subtitleColor ?? themeYellow)),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(subtitle,
                  style: TextStyle(color: subtitleColor ?? Colors.grey, fontSize: 8, fontWeight: FontWeight.w500)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTablesCard(FirebaseFirestore firestore, String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('tables')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('status', isNotEqualTo: 'available')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildStatCard("Occupied", count.toString(), Icons.table_bar, Colors.green);
      },
    );
  }

  Widget _buildPendingKotsCard(FirebaseFirestore firestore, String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('status', whereIn: ['open', 'kotSent', 'Preparing']) // Preparing added for future-proofing
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildStatCard("Pending", count.toString(), Icons.timer, Colors.red);
      },
    );
  }

  Widget _buildMonthlyBarChart(FirebaseFirestore firestore, DateTime startOfYear, String? restaurantId) {
    final now = DateTime.now();
    final monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        
        final Map<int, double> monthlyRevenue = { for (int i = 0; i < 12; i++) i: 0 };

        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['status'] != 'billed') continue;
            if (data['createdAt'] == null) continue;
            
            final createdAt = (data['createdAt'] as Timestamp).toDate();
            if (createdAt.year == now.year) {
              final m = createdAt.month - 1;
              monthlyRevenue[m] = (monthlyRevenue[m] ?? 0) + (data['totalAmount'] ?? 0).toDouble();
            }
          }
        }

        final maxRevenue = monthlyRevenue.values.fold<double>(0, (a, b) => a > b ? a : b);

        return Container(
          height: 250,
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${now.year} Revenue Trend", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              const SizedBox(height: 16),
              Expanded(
                child: BarChart(
                  BarChartData(
                    backgroundColor: const Color(0xFF1E1E1E),
                    maxY: maxRevenue > 0 ? maxRevenue * 1.2 : 100,
                    barGroups: List.generate(12, (i) {
                      final isCurrent = i == now.month - 1;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: monthlyRevenue[i] ?? 0,
                            width: 12,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            color: isCurrent ? const Color(0xFFE7FF12) : const Color(0xFFE7FF12).withOpacity(0.15),
                          ),
                        ],
                      );
                    }),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= 12) return const SizedBox.shrink();
                            return Text(monthNames[i], style: const TextStyle(fontSize: 9, color: Colors.white54));
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxRevenue > 0 ? maxRevenue / 4 : 25, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1)),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOrderDetailDialog(String title, List<QueryDocumentSnapshot> orders) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: orders.isEmpty 
              ? const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text("No orders found for this period.", style: TextStyle(color: Colors.white54)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05)),
                  itemBuilder: (context, index) {
                    final data = orders[index].data() as Map<String, dynamic>;
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                    final amount = (data['totalAmount'] ?? 0).toDouble();
                    final waiter = data['waiterName'] ?? 'Unknown';
                    final customer = data['customerName'] ?? 'Walk-in';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFE7FF12).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.receipt_long, color: Color(0xFFE7FF12), size: 20),
                      ),
                      title: Text("${data['tableName']} - ₹${amount.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("$customer • $waiter", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          Text(DateFormat('hh:mm a').format(createdAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.print, color: Color(0xFFE7FF12), size: 18),
                        onPressed: () => ReportService.printOrderReceipt(data, orders[index].id),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

