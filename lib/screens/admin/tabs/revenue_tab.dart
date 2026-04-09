import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;

    if (restaurantId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF141615),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22))),
      );
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text("Administration Overview", 
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFFFCDD22)),
                onPressed: () => setState(() {}),
                tooltip: "Refresh Dashboard",
              ),
            ],
          ),
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
          StreamBuilder<DocumentSnapshot>(
            stream: firestore.collection('daily_collections')
                .doc("${restaurantId}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}")
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.hasData && snapshot.data!.exists 
                  ? snapshot.data!.data() as Map<String, dynamic>?
                  : null;
              return _buildTodayStats(context, data, snapshot.error, firestore, restaurantId);
            },
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text("Data Source: $restaurantId • Live Sync Active", 
              style: const TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 24),
          _buildRevenueAnalyticsLayout(firestore, restaurantId),
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
            color: const Color(0xFFFCDD22).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFFFCDD22), size: 18),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(title, 
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFFCDD22).withOpacity(0.2), thickness: 1.5)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? subtitle, Color? subtitleColor, VoidCallback? onTap}) {
    final themeYellow = const Color(0xFFFCDD22);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: const Color(0xFF141615),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: themeYellow.withOpacity(0.05), width: 1),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: themeYellow.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: subtitleColor ?? themeYellow, size: 12),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(title,
                    style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: subtitleColor ?? themeYellow)),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 0),
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
      ),
    );
  }

  Widget _buildRevenueAnalyticsLayout(FirebaseFirestore firestore, String? restaurantId) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOf7DaysAgo = startOfToday.subtract(const Duration(days: 6));
    final endOfToday = startOfToday.add(const Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      // Optimization: Fetch the latest 1000 orders globally and filter in-memory.
      // This avoids composite index requirements and handles orders with missing restaurantId.
      stream: firestore.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .orderBy('createdAt', descending: true)
          .limit(1000)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("Analytics Stream Error: ${snapshot.error}");
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Text("Error loading analytics. Please check connection.", style: const TextStyle(color: Colors.white70, fontSize: 12)),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFFFCDD22))));
        }

        final docs = snapshot.data?.docs ?? [];

        // Filter and normalize orders in-memory
        List<Map<String, dynamic>> todayOrders = [];
        final Map<int, double> revenueByDay = {for (int i = 0; i < 7; i++) i: 0};

        DateTime? getOrderDate(Map<String, dynamic> data) {
          return (data['billedAt'] as Timestamp?)?.toDate() ?? 
                 (data['createdAt'] as Timestamp?)?.toDate();
        }

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          
          // 0. Filter Restaurant (Safe Fallback)
          if (restaurantId != null && data['restaurantId'] != null) {
            if (data['restaurantId'] != restaurantId) continue;
          }

          // 1. Filter Status
          final status = data['status']?.toString() ?? '';
          if (status != 'billed' && status != 'completed') continue;

          // 2. Filter Date
          final orderDate = getOrderDate(data);
          if (orderDate == null) continue;

          final orderDay = DateTime(orderDate.year, orderDate.month, orderDate.day);
          if (orderDay.isBefore(startOf7DaysAgo) || !orderDay.isBefore(endOfToday)) continue;

          final total = (data['totalAmount'] ?? data['grandTotal'] ?? data['subtotal'] ?? 0);
          final totalDouble = total is num ? total.toDouble() : double.tryParse(total.toString()) ?? 0;

          final dayIndex = orderDay.difference(startOf7DaysAgo).inDays;
          if (dayIndex >= 0 && dayIndex < 7) {
            revenueByDay[dayIndex] = (revenueByDay[dayIndex] ?? 0) + totalDouble;
          }

          // For the "Recent Orders" table, we include everything from the last 24 hours
          // This prevents orders from disappearing due to midnight rollovers or clock drift.
          final isRecent = orderDate.isAfter(DateTime.now().subtract(const Duration(hours: 24)));
          if (!isRecent) continue;

          todayOrders.add({
            'id': doc.id,
            'receiptNumber': data['receiptNumber'],
            'tableName': data['tableName'] ?? data['orderType'] ?? 'N/A',
            'orderType': data['orderType'] ?? '',
            'paymentMode': data['paymentMode'] ?? '',
            'totalAmount': totalDouble,
            'billedAt': orderDate,
            'items': data['items'] as List?,
          });
        }

        if (todayOrders.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text("No billed orders found for today.", style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          );
        }

        final labels = List.generate(7, (i) {
          final d = startOf7DaysAgo.add(Duration(days: i));
          return DateFormat('EEE').format(d);
        });
        final weekRevenue = List.generate(7, (i) => revenueByDay[i] ?? 0.0);
        final topRecentOrders = List<Map<String, dynamic>>.from(todayOrders)
          ..sort((a, b) => (b['billedAt'] as DateTime).compareTo(a['billedAt'] as DateTime));
        topRecentOrders.length = topRecentOrders.length > 10 ? 10 : topRecentOrders.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSalesTrendLineChartContainer(labels, weekRevenue),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildSectionHeader("Recent Orders", Icons.receipt_long, const Color(0xFFFCDD22))),
              ],
            ),
            const SizedBox(height: 16),
            _buildRecentOrdersTable(topRecentOrders),
          ],
        );
      },
    );
  }

  Widget _buildCategoryPieChartContainer(List<Map<String, dynamic>> topCategories, double totalRevenue) {
    if (topCategories.isEmpty || totalRevenue <= 0) {
      return Container(
        height: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141615),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: const Center(child: Text("No category data", style: TextStyle(color: Colors.white38, fontSize: 12))),
      );
    }

    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Category Distribution (Today)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
          const SizedBox(height: 12),
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 35,
                sections: topCategories.asMap().entries.map((entry) {
                  final i = entry.key;
                  final c = entry.value;
                  final revenue = c['revenue'] as double;
                  final percentage = (revenue / totalRevenue) * 100;
                  return PieChartSectionData(
                    value: revenue,
                    title: "${percentage.toStringAsFixed(0)}%",
                    radius: 60,
                    color: Colors.primaries[i % Colors.primaries.length],
                    titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: topCategories.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              final name = c['name'] as String;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.primaries[i % Colors.primaries.length], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text(name, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              );
            }).toList(),
          )
        ],
      ),
    );
  }

  Widget _buildSalesTrendLineChartContainer(List<String> labels, List<double> revenue) {
    final maxY = revenue.fold<double>(0, (a, b) => a > b ? a : b);
    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Sales Trend (Last 7 Days)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                maxY: maxY > 0 ? maxY * 1.15 : 100,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY > 0 ? maxY / 4 : 25),
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1, // FIX: Prevents repeated day labels
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(labels[i], style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(revenue.length, (i) => FlSpot(i.toDouble(), revenue[i])).toList(),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFFFCDD22),
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFFCDD22).withOpacity(0.2),
                          const Color(0xFFFCDD22).withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => const Color(0xFF1A1D1C),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          "₹${spot.y.toStringAsFixed(0)}",
                          const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text("Max Point: ₹${maxY.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildRecentOrdersTable(List<Map<String, dynamic>> recentOrders) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(const Color(0xFF141615)),
          headingTextStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11),
          dataTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text("BILL #")),
            DataColumn(label: Text("TABLE")),
            DataColumn(label: Text("TYPE")),
            DataColumn(label: Text("PAYMENT")),
            DataColumn(label: Text("TOTAL"), numeric: true),
          ],
          rows: recentOrders.map((o) {
            final receipt = o['receiptNumber']?.toString() ?? '';
            final tableName = o['tableName']?.toString() ?? '';
            final orderType = o['orderType']?.toString() ?? '';
            final payment = o['paymentMode']?.toString() ?? '';
            final total = (o['totalAmount'] as double?) ?? 0;

            return DataRow(
              cells: [
                DataCell(Text(receipt.isNotEmpty ? receipt : '—')),
                DataCell(Text(tableName.isNotEmpty ? tableName : '—')),
                DataCell(Text(orderType.toString().toUpperCase())),
                DataCell(Text(payment.toString().toUpperCase())),
                DataCell(Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActiveTablesCard(FirebaseFirestore firestore, String? restaurantId, {VoidCallback? onTap}) {
    return kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: firestore.collection('tables')
              .where('restaurantId', isEqualTo: restaurantId)
              .where('status', isNotEqualTo: 'available')
              .get(),
          builder: (context, snapshot) {
            final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
            return _buildStatCard("Occupied", count.toString(), Icons.table_bar, Colors.green, onTap: onTap);
          },
        )
      : StreamBuilder<QuerySnapshot>(
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
    return kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .where('status', whereIn: ['open', 'kotSent', 'Preparing'])
              .get(),
          builder: (context, snapshot) {
            final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
            return _buildStatCard("Pending", count.toString(), Icons.timer, Colors.red, onTap: onTap);
          },
        )
      : StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .where('status', whereIn: ['open', 'kotSent', 'Preparing'])
              .snapshots(),
          builder: (context, snapshot) {
            final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
            return _buildStatCard("Pending", count.toString(), Icons.timer, Colors.red, onTap: onTap);
          },
        );
  }

  Widget _buildOnlineSourceCard(
    FirebaseFirestore firestore,
    String? restaurantId, {
    required String sourceKey,
    required String title,
    required Color color,
    required IconData icon,
  }) {
    final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    double revenueFrom(QuerySnapshot snapshot) {
      var revenue = 0.0;
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status != 'billed' && status != 'completed') continue;

        final billedAt = (data['billedAt'] as Timestamp?)?.toDate() ??
            (data['createdAt'] as Timestamp?)?.toDate();
        if (billedAt == null || billedAt.isBefore(startOfDay) || !billedAt.isBefore(endOfDay)) {
          continue;
        }

        final source = (data['orderSource'] ?? data['channel'] ?? '').toString().toLowerCase().trim();
        if (source != sourceKey) continue;
        revenue += ((data['totalAmount'] ?? data['grandTotal'] ?? 0) as num).toDouble();
      }
      return revenue;
    }

    int countFrom(QuerySnapshot snapshot) {
      var count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status != 'billed' && status != 'completed') continue;

        final billedAt = (data['billedAt'] as Timestamp?)?.toDate() ??
            (data['createdAt'] as Timestamp?)?.toDate();
        if (billedAt == null || billedAt.isBefore(startOfDay) || !billedAt.isBefore(endOfDay)) {
          continue;
        }

        final source = (data['orderSource'] ?? data['channel'] ?? '').toString().toLowerCase().trim();
        if (source == sourceKey) count++;
      }
      return count;
    }

    return kIsWeb
        ? FutureBuilder<QuerySnapshot>(
            future: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).get(),
            builder: (context, snapshot) {
              final revenue = snapshot.hasData ? revenueFrom(snapshot.data!) : 0.0;
              final count = snapshot.hasData ? countFrom(snapshot.data!) : 0;
              return _buildStatCard(
                title,
                "₹${revenue.toStringAsFixed(0)}",
                icon,
                color,
                subtitle: "$count Orders",
                onTap: () => _showTodayDetails(sourceKey),
              );
            },
          )
        : StreamBuilder<QuerySnapshot>(
            stream: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).snapshots(),
            builder: (context, snapshot) {
              final revenue = snapshot.hasData ? revenueFrom(snapshot.data!) : 0.0;
              final count = snapshot.hasData ? countFrom(snapshot.data!) : 0;
              return _buildStatCard(
                title,
                "₹${revenue.toStringAsFixed(0)}",
                icon,
                color,
                subtitle: "$count Orders",
                onTap: () => _showTodayDetails(sourceKey),
              );
            },
          );
  }
  Widget _buildTodayStats(BuildContext context, Map<String, dynamic>? data, Object? error, FirebaseFirestore firestore, String? restaurantId) {
    double todayRevenue = 0;
    double todayTableRevenue = 0;
    double todayTakeawayRevenue = 0;
    double todayDeliveryRevenue = 0;
    double todayOnlineRevenue = 0;
    int billCount = 0;
    int takeawayCount = 0;
    int deliveryCount = 0;
    int tableCount = 0;
    int onlineCount = 0;
    double todayCashRevenue = 0;
    double todayUpiRevenue = 0;

    if (error != null) {
      debugPrint("AdminDashboard: Error fetching stats: $error");
      // Gracefully hide error message as per user request and return empty placeholder or zeroed cards
      return const SizedBox.shrink(); 
    }

    if (data != null) {
      todayRevenue = (data['netCollection'] ?? 0).toDouble();
      todayTableRevenue = (data['tableCollection'] ?? 0).toDouble();
      todayTakeawayRevenue = (data['takeawayCollection'] ?? 0).toDouble();
      todayDeliveryRevenue = (data['deliveryCollection'] ?? 0).toDouble();
      todayOnlineRevenue = (data['onlineCollection'] ?? 0).toDouble();
      billCount = (data['billCount'] ?? 0).toInt();
      takeawayCount = (data['takeawayCount'] ?? 0).toInt();
      deliveryCount = (data['deliveryCount'] ?? 0).toInt();
      tableCount = (data['tableCount'] ?? 0).toInt();
      onlineCount = (data['onlineCount'] ?? 0).toInt();
      todayCashRevenue = (data['cashCollection'] ?? 0).toDouble();
      todayUpiRevenue = (data['upiCollection'] ?? 0).toDouble();
    }

    final width = MediaQuery.of(context).size.width;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: width > 900 ? 5 : (width > 600 ? 4 : (width < 320 ? 2 : 3)), 
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: width > 600 ? 1.0 : 0.85,
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
          const Color(0xFFFCDD22),
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
          "Delivery Sales", 
          "₹${todayDeliveryRevenue.toStringAsFixed(0)}", 
          Icons.delivery_dining, 
          Colors.deepOrange,
          subtitle: "$deliveryCount Orders",
          onTap: () => _showTodayDetails('delivery'),
        ),
        _buildOnlineSourceCard(
          firestore,
          restaurantId,
          sourceKey: 'zomato',
          title: "Zomato",
          color: Colors.redAccent,
          icon: Icons.local_mall,
        ),
        _buildOnlineSourceCard(
          firestore,
          restaurantId,
          sourceKey: 'swiggy',
          title: "Swiggy",
          color: Colors.orangeAccent,
          icon: Icons.delivery_dining,
        ),
        _buildOnlineSourceCard(
          firestore,
          restaurantId,
          sourceKey: 'uber',
          title: "Uber",
          color: Colors.greenAccent,
          icon: Icons.local_taxi,
        ),
        _buildStatCard(
          "Cash Sales", 
          "₹${todayCashRevenue.toStringAsFixed(0)}", 
          Icons.payments, 
          Colors.greenAccent,
          subtitle: "Total Cash",
          onTap: () => _showTodayDetails('Total'),
        ),
        _buildStatCard(
          "UPI Sales", 
          "₹${todayUpiRevenue.toStringAsFixed(0)}", 
          Icons.qr_code_scanner, 
          Colors.blue,
          subtitle: "Total UPI",
          onTap: () => _showTodayDetails('Total'),
        ),
        _buildActiveTablesCard(firestore, restaurantId, onTap: () => widget.onTabRequested?.call(4)),
        _buildPendingKotsCard(firestore, restaurantId, onTap: () => _showTodayDetails('Pending')),
      ],
    );
  }

  Widget _buildMonthlyBarChart(FirebaseFirestore firestore, DateTime startOfYear, String? restaurantId) {
    final now = DateTime.now();
    final monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .get(),
          builder: (context, snapshot) => _buildChartContent(context, snapshot, now, monthNames),
        )
      : StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .snapshots(),
          builder: (context, snapshot) => _buildChartContent(context, snapshot, now, monthNames),
        );
  }

  Widget _buildChartContent(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot, DateTime now, List<String> monthNames) {
    if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
    
    final Map<int, double> monthlyRevenue = { for (int i = 0; i < 12; i++) i: 0 };

    if (snapshot.hasData) {
      for (var doc in snapshot.data!.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status']?.toString() ?? '';
        if (status != 'billed' && status != 'completed') continue;
        if (data['billedAt'] == null) continue;
        
        final billedAt = (data['billedAt'] as Timestamp).toDate();
        if (billedAt.year == now.year) {
          final m = billedAt.month - 1;
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
        color: const Color(0xFF141615),
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
                backgroundColor: const Color(0xFF141615),
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
                        color: isCurrent ? const Color(0xFFFCDD22) : const Color(0xFFFCDD22).withOpacity(0.15),
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
  }

  void _showTodayDetails(String type) async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      // NOTE:
      // Some existing `orders` documents (especially after Windows settle/bill)
      // may not contain `restaurantId`. Your security rules can still allow
      // reads via `tableId -> tables.restaurantId`, so we fetch without the
      // strict `restaurantId` filter and then filter in-memory.
      Query query = FirebaseFirestore.instance.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId);
      
      if (type == 'Pending') {
        query = query.where('status', whereIn: ['open', 'kotSent', 'Preparing'])
                     .orderBy('createdAt', descending: true)
                     .limit(500);
      } else {
        query = query.orderBy('createdAt', descending: true).limit(1000);
      }

      final snapshot = await query.get();
      if (mounted) {
        Navigator.pop(context);
        Future.microtask(() {
          if (mounted) {
            List<QueryDocumentSnapshot> docs = snapshot.docs;

            if (type != 'Pending') {
              String norm(Object? v) =>
                  (v?.toString() ?? '').trim().toLowerCase().replaceAll(' ', '_');

              docs = snapshot.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;

                // 0. Filter Restaurant (Safe Fallback)
                if (restaurantId != null && data['restaurantId'] != null) {
                  if (data['restaurantId'] != restaurantId) return false;
                }

                // 1. Filter Status
                final status = data['status']?.toString() ?? '';
                if (status != 'billed' && status != 'completed') return false;

                // 2. Normalize and Filter Date (Match Dashboard logic)
                DateTime? orderDate = (data['billedAt'] as Timestamp?)?.toDate() ?? 
                                      (data['createdAt'] as Timestamp?)?.toDate();
                if (orderDate == null) return false;
                
                final isToday = orderDate.year == startOfDay.year && 
                                orderDate.month == startOfDay.month && 
                                orderDate.day == startOfDay.day;
                if (!isToday) return false;

                if (type == 'Total') return true;

                // 3. Filter Category/Type mapping
                final orderType = norm(data['orderType']);
                final orderSource = norm(data['orderSource']);

                // Card mapping
                if (type == 'table') {
                  return orderType == 'dine_in' || orderSource == 'dine_in';
                }
                if (type == 'takeaway') {
                  return orderType == 'takeaway' || orderSource == 'takeaway';
                }
                if (type == 'delivery') {
                  return orderType == 'delivery' || orderSource == 'delivery';
                }
                if (type == 'online') {
                  const onlineSources = [
                    'zomato',
                    'swiggy',
                    'uber',
                    'urbanpiper',
                    'urban_piper',
                  ];
                  return orderType == 'online' || onlineSources.contains(orderSource);
                }
                if (type == 'zomato' || type == 'swiggy' || type == 'uber') {
                  return orderSource == type;
                }

                return true;
              }).toList();

              // --- FALLBACK LOGIC ---
              // If "today" is empty, but the card showed revenue, it may be a date mismatch.
              // We'll show the most recent orders from the last 24 hours as a fallback.
              if (docs.isEmpty && type != 'Pending') {
                final last24H = DateTime.now().subtract(const Duration(hours: 24));
                docs = snapshot.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status']?.toString() ?? '';
                  if (status != 'billed' && status != 'completed') return false;
                  
                  DateTime? orderDate = (data['billedAt'] as Timestamp?)?.toDate() ?? 
                                        (data['createdAt'] as Timestamp?)?.toDate();
                  if (orderDate == null || orderDate.isBefore(last24H)) return false;
                  
                  if (type == 'Total') return true;
                  
                  final orderType = norm(data['orderType']);
                  final orderSource = norm(data['orderSource']);
                  // Re-apply type filtering
                  if (type == 'table') return orderType == 'dine_in' || orderSource == 'dine_in';
                  if (type == 'takeaway') return orderType == 'takeaway' || orderSource == 'takeaway';
                  if (type == 'delivery') return orderType == 'delivery' || orderSource == 'delivery';
                  if (type == 'online') return orderType == 'online' || ['zomato', 'swiggy', 'uber'].contains(orderSource);
                  if (type == 'zomato' || type == 'swiggy' || type == 'uber') return orderSource == type;
                  return true;
                }).toList();
              }
            }

            _showOrderDetailDialog(
              "Today's ${type[0].toUpperCase()}${type.substring(1)} Details",
              docs,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showOrderDetailDialog(String title, List<QueryDocumentSnapshot> orders) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
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
        content: SizedBox(
          width: MediaQuery.of(context).size.width > 600 ? 500 : MediaQuery.of(context).size.width * 0.9,
          height: 600,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              const Divider(color: Colors.white10),
              Expanded(
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
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final data = orders[index].data() as Map<String, dynamic>;
                          final billedAt = (data['billedAt'] as Timestamp?)?.toDate() ?? 
                                             (data['createdAt'] as Timestamp?)?.toDate() ?? 
                                             DateTime.now();
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
                                  decoration: BoxDecoration(color: const Color(0xFFFCDD22).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.receipt_long, color: Color(0xFFFCDD22), size: 20),
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
                                    Text(DateFormat('hh:mm a').format(billedAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.print, color: Color(0xFFFCDD22), size: 18),
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
