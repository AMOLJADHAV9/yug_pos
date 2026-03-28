import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../services/report_service.dart';
import '../../../services/auth_service.dart';
import 'package:provider/provider.dart';

class RevenueTab extends StatefulWidget {
  final Function(int)? onTabRequested;
  const RevenueTab({super.key, this.onTabRequested});

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
                  crossAxisCount: width > 900 ? 5 : (width > 600 ? 4 : (width < 300 ? 2 : 3)), 
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: width > 600 ? 1.0 : 0.95,
                  children: [
                    _buildStatCard(
                      "Daily Total", 
                      "₹${todayRevenue.toStringAsFixed(0)}", 
                      Icons.currency_rupee, 
                      Colors.green,
                      subtitle: "Total ($billCount Bills)",
                      onTap: () => _showTodayDetails('Total'),
                    ),
                    _buildStatCard(
                      "Table Sales", 
                      "₹${todayTableRevenue.toStringAsFixed(0)}", 
                      Icons.restaurant, 
                      const Color(0xFFE7FF12),
                      subtitle: "$tableCount Orders",
                      onTap: () => _showTodayDetails('table'),
                    ),
                    _buildStatCard(
                      "Takeaway Sales", 
                      "₹${todayTakeawayRevenue.toStringAsFixed(0)}", 
                      Icons.shopping_bag, 
                      Colors.purpleAccent,
                      subtitle: "$takeawayCount Orders",
                      onTap: () => _showTodayDetails('takeaway'),
                    ),
                    _buildStatCard(
                      "Online Sales", 
                      "₹${todayOnlineRevenue.toStringAsFixed(0)}", 
                      Icons.cloud_download, 
                      Colors.blueAccent,
                      subtitle: "$onlineCount Z/S Orders",
                      onTap: () => _showTodayDetails('online'),
                    ),
                    _buildActiveTablesCard(firestore, restaurantId, onTap: () => widget.onTabRequested?.call(4)), // Still switch tab for tables
                    _buildPendingKotsCard(firestore, restaurantId, onTap: () => _showTodayDetails('Pending')),
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
        Flexible(
          child: Text(title, 
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFE7FF12).withOpacity(0.2), thickness: 1.5)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? subtitle, Color? subtitleColor, VoidCallback? onTap}) {
    final themeYellow = const Color(0xFFE7FF12);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: themeYellow.withOpacity(0.05), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, // Ensure we stay compact
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
      ),
    );
  }

  Widget _buildActiveTablesCard(FirebaseFirestore firestore, String? restaurantId, {VoidCallback? onTap}) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('tables')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('status', isNotEqualTo: 'available')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildStatCard("Occupied", count.toString(), Icons.table_bar, Colors.green, onTap: onTap);
      },
    );
  }

  Widget _buildPendingKotsCard(FirebaseFirestore firestore, String? restaurantId, {VoidCallback? onTap}) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('status', whereIn: ['open', 'kotSent', 'Preparing']) // Preparing added for future-proofing
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildStatCard("Pending", count.toString(), Icons.timer, Colors.red, onTap: onTap);
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

  void _showTodayDetails(String type) async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      Query query = FirebaseFirestore.instance.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId);
      
      if (type == 'Pending') {
        query = query.where('status', whereIn: ['open', 'kotSent', 'Preparing']);
      } else {
        query = query.where('createdAt', isGreaterThanOrEqualTo: startOfDay);
        if (type != 'Total') {
          query = query.where('orderType', isEqualTo: type.toLowerCase());
        }
      }

      final snapshot = await query.get();
      if (mounted) Navigator.pop(context);

      _showOrderDetailDialog("Today's ${type[0].toUpperCase()}${type.substring(1)} Details", snapshot.docs);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showOrderDetailDialog(String title, List<QueryDocumentSnapshot> orders) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        title: Row(
          children: [
            Expanded(
              child: Text(title, 
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(color: Colors.white10),
              Flexible(
                child: orders.isEmpty 
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 48, color: Colors.white10),
                            SizedBox(height: 16),
                            Text("No orders found today.", style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final data = orders[index].data() as Map<String, dynamic>;
                          final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                          final amount = (data['totalAmount'] ?? 0).toDouble();
                          final waiter = data['waiterName'] ?? 'Unknown';
                          final customer = data['customerName'] ?? 'Walk-in';

                          final titlePrefix = data['tableName'] ?? 
                                               (data['orderType']?.toString().toUpperCase() ?? 
                                                data['orderSource']?.toString().toUpperCase() ?? 'ORDER');
                          
                          return Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: const Color(0xFFE7FF12).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.receipt_long, color: Color(0xFFE7FF12), size: 20),
                                ),
                                title: Text("$titlePrefix - ₹${amount.toStringAsFixed(0)}", 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("$customer • $waiter", 
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    Text(DateFormat('hh:mm a').format(createdAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.print, color: Color(0xFFE7FF12), size: 18),
                                  onPressed: () => ReportService.printOrderReceipt(data, orders[index].id),
                                ),
                              ),
                              Divider(color: Colors.white.withOpacity(0.05)),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

