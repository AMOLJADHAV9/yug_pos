import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../services/auth_service.dart';
import '../../../services/report_service.dart';
import 'package:provider/provider.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final today = DateTime.now();
    final startOfThisMonth = DateTime(today.year, today.month, 1);
    final startOfLastMonth = DateTime(today.year, today.month - 1, 1);
    final startOfYear = DateTime(today.year, 1, 1);

    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;

    if (restaurantId == null) {
      return const Scaffold(
        backgroundColor: const Color(0xFF141615),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22))),
      );
    }

    return kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).get(),
          builder: (context, snapshot) => _buildAnalyticsContent(context, snapshot, startOfThisMonth, startOfLastMonth, startOfYear, today),
        )
      : StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).snapshots(),
          builder: (context, snapshot) => _buildAnalyticsContent(context, snapshot, startOfThisMonth, startOfLastMonth, startOfYear, today),
        );
  }

  Widget _buildAnalyticsContent(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot, DateTime startOfThisMonth, DateTime startOfLastMonth, DateTime startOfYear, DateTime today) {
    final firestore = FirebaseFirestore.instance;
    final restaurantId = context.read<AuthService>().restaurantId;

    if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

    double thisMonthRevenue = 0;
    double lastMonthRevenue = 0;
    double thisWeekRevenue = 0;
    int thisMonthOrders = 0;
    int thisWeekOrders = 0;

    final sevenDaysAgo = today.subtract(const Duration(days: 7));

    if (snapshot.hasData) {
      for (var doc in snapshot.data!.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status']?.toString() ?? '';
        if (status != 'billed' && status != 'completed') continue;
        if (data['createdAt'] == null) continue;
        
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        if (createdAt.isBefore(startOfLastMonth)) continue;
        
        final amount = (data['totalAmount'] ?? 0).toDouble();

        if (createdAt.isAfter(startOfThisMonth)) {
          thisMonthRevenue += amount;
          thisMonthOrders++;
        } else if (createdAt.isAfter(startOfLastMonth) && createdAt.isBefore(startOfThisMonth)) {
          lastMonthRevenue += amount;
        }

        if (createdAt.isAfter(sevenDaysAgo)) {
          thisWeekRevenue += amount;
          thisWeekOrders++;
        }
      }
    }

    String monthTrend = "";
    Color trendColor = Colors.grey;
    if (lastMonthRevenue > 0) {
      final growth = ((thisMonthRevenue - lastMonthRevenue) / lastMonthRevenue) * 100;
      monthTrend = "${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(1)}% vs last month";
      trendColor = growth >= 0 ? Colors.green : Colors.red;
    }

    final width = MediaQuery.of(context).size.width;
    int crossAxis = width > 900 ? 4 : (width > 600 ? 3 : 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Analytics & Reports", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFFFCDD22)),
                onPressed: () => setState(() {}),
                tooltip: "Refresh Analytics",
              ),
            ],
          ),
          const SizedBox(height: 24),

          _buildSectionHeader("Performance Overview", Icons.bar_chart, const Color(0xFF800000)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxis,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: width > 1200 ? 1.8 : (width > 600 ? 1.3 : 1.4),
            children: [
              InkWell(
                onTap: () {
                  final thisMonthOrdersList = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status']?.toString() ?? '';
                    if ((status != 'billed' && status != 'completed') || data['createdAt'] == null) return false;
                    final createdAt = (data['createdAt'] as Timestamp).toDate();
                    return createdAt.isAfter(startOfThisMonth);
                  }).toList();
                  _showOrderDetailDialog("This Month's Orders", thisMonthOrdersList);
                },
                child: _buildStatCard(
                  "This Month (${DateFormat('MMMM').format(today)})",
                  "₹${thisMonthRevenue.toStringAsFixed(0)}",
                  Icons.calendar_month,
                  const Color(0xFF800000),
                  subtitle: monthTrend,
                  subtitleColor: trendColor,
                ),
              ),
              InkWell(
                onTap: () {
                  final thisWeekOrdersList = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status']?.toString() ?? '';
                    if ((status != 'billed' && status != 'completed') || data['createdAt'] == null) return false;
                    final createdAt = (data['createdAt'] as Timestamp).toDate();
                    return createdAt.isAfter(sevenDaysAgo);
                  }).toList();
                  _showOrderDetailDialog("This Week's Orders", thisWeekOrdersList);
                },
                child: _buildStatCard(
                  "This Week (7 Days)",
                  "₹${thisWeekRevenue.toStringAsFixed(0)}",
                  Icons.view_week,
                  Colors.amber,
                  subtitle: "$thisWeekOrders Orders Recorded",
                  subtitleColor: Colors.amberAccent,
                ),
              ),
              InkWell(
                onTap: () {
                  final lastMonthOrdersList = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status']?.toString() ?? '';
                    if ((status != 'billed' && status != 'completed') || data['createdAt'] == null) return false;
                    final createdAt = (data['createdAt'] as Timestamp).toDate();
                    return createdAt.isAfter(startOfLastMonth) && createdAt.isBefore(startOfThisMonth);
                  }).toList();
                  _showOrderDetailDialog("Last Month's Orders", lastMonthOrdersList);
                },
                child: _buildStatCard(
                  "Last Month (${DateFormat('MMMM').format(startOfLastMonth)})",
                  "₹${lastMonthRevenue.toStringAsFixed(0)}",
                  Icons.calendar_today,
                  Colors.indigo,
                ),
              ),
              InkWell(
                onTap: () {
                  final thisMonthOrdersList = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status']?.toString() ?? '';
                    if ((status != 'billed' && status != 'completed') || data['createdAt'] == null) return false;
                    final createdAt = (data['createdAt'] as Timestamp).toDate();
                    return createdAt.isAfter(startOfThisMonth);
                  }).toList();
                  _showOrderDetailDialog("This Month's Orders", thisMonthOrdersList);
                },
                child: _buildStatCard(
                  "Monthly Orders",
                  thisMonthOrders.toString(),
                  Icons.receipt,
                  Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildMonthlyBarChart(firestore, startOfYear, restaurantId),
          const SizedBox(height: 40),

          _buildSectionHeader("Distribution & Trends", Icons.analytics, Colors.blue),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              SizedBox(
                width: width > 1200 ? (width - 100) / 2 : double.infinity,
                child: _buildCategoryPieChart(firestore, restaurantId),
              ),
              SizedBox(
                width: width > 1200 ? (width - 100) / 2 : double.infinity,
                child: _buildWeeklyLineChart(firestore, restaurantId),
              ),
            ],
          ),
          const SizedBox(height: 40),

          _buildSectionHeader("Product Performance", Icons.trending_up, Colors.orange),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              SizedBox(
                width: width > 1200 ? (width - 100) / 2 : double.infinity,
                child: _buildTrendingMenuSection(snapshot),
              ),
              SizedBox(
                width: width > 1200 ? (width - 100) / 2 : double.infinity,
                child: _buildCategoryColumnChart(snapshot),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
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
          builder: (context, snapshot) => _buildBarChartContent(context, snapshot, now, monthNames),
        )
      : StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .snapshots(),
          builder: (context, snapshot) => _buildBarChartContent(context, snapshot, now, monthNames),
        );
  }

  Widget _buildBarChartContent(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot, DateTime now, List<String> monthNames) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.red)));
    }
    
    final Map<int, double> monthlyRevenue = { for (int i = 0; i < 12; i++) i: 0 };

    if (snapshot.hasData) {
      for (var doc in snapshot.data!.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] == 'cancelled') continue;
        if (data['createdAt'] == null) continue;
        
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        // In-memory filter for this year
        if (createdAt.year == now.year) {
          final m = createdAt.month - 1;
          monthlyRevenue[m] = (monthlyRevenue[m] ?? 0) + (data['totalAmount'] ?? 0).toDouble();
        }
      }
    }

    final maxRevenue = monthlyRevenue.values.fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Color(0xFFFCDD22), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text("${now.year} Revenue Trend", 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                backgroundColor: const Color(0xFF141615),
                maxY: maxRevenue > 0 ? maxRevenue * 1.2 : 100,
                barGroups: List.generate(12, (i) {
                  final isCurrent = i == now.month - 1;
                  final isPast = i < now.month - 1;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: monthlyRevenue[i] ?? 0,
                        width: MediaQuery.of(context).size.width < 600 ? 8 : 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        color: isCurrent ? const Color(0xFFFCDD22) : (isPast ? const Color(0xFFFCDD22).withOpacity(0.4) : Colors.white.withOpacity(0.1)),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, meta) {
                        if (v == meta.max) return const SizedBox.shrink();
                        if (v >= 1000) return Text('${(v / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 8, color: Colors.white54));
                        return Text('${v.toStringAsFixed(0)}', style: const TextStyle(fontSize: 8, color: Colors.white54));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= 12) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Transform.rotate(
                            angle: -0.6,
                            child: Text(monthNames[i], style: const TextStyle(fontSize: 7, color: Colors.white54, fontWeight: FontWeight.bold)),
                          ),
                        );
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

  Widget _buildCategoryPieChart(FirebaseFirestore firestore, String? restaurantId) {
    return kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).get(),
          builder: (context, snapshot) => _buildPieChartContent(context, snapshot),
        )
      : StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).snapshots(),
          builder: (context, snapshot) => _buildPieChartContent(context, snapshot),
        );
  }

  Widget _buildPieChartContent(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
    if (!snapshot.hasData) return SizedBox(height: MediaQuery.of(context).size.width < 600 ? 280 : 350, child: const Center(child: CircularProgressIndicator()));
    Map<String, double> catRevenue = {};
    for (var doc in snapshot.data!.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final items = data['items'] as List? ?? [];
      for (var it in items) {
         final cat = it['category'] ?? 'General';
         catRevenue[cat] = (catRevenue[cat] ?? 0) + ((it['price'] ?? 0) * (it['quantity'] ?? 1));
      }
    }
    double total = catRevenue.values.fold(0, (sum, v) => sum + v);
    if (total == 0) return const Center(child: Text("No data available"));

    return Container(
      height: MediaQuery.of(context).size.width < 600 ? 280 : 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF141615), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        children: [
          const Text("Category Distribution (%)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          const SizedBox(height: 16),
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: catRevenue.entries.map((e) {
                  final percentage = (e.value / total) * 100;
                  final index = catRevenue.keys.toList().indexOf(e.key);
                  return PieChartSectionData(
                    value: e.value, 
                    title: "${percentage.toStringAsFixed(0)}%", 
                    radius: 60, 
                    color: Colors.primaries[index % Colors.primaries.length], // Categories can keep distinct colors for differentiation
                    titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }).toList()
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: catRevenue.keys.map((cat) {
              final index = catRevenue.keys.toList().indexOf(cat);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, color: Colors.primaries[index % Colors.primaries.length]),
                  const SizedBox(width: 4),
                  Text(cat, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              );
            }).toList(),
          )
        ],
      ),
    );
  }

  Widget _buildWeeklyLineChart(FirebaseFirestore firestore, String? restaurantId) {
    final twelveWeeksAgo = DateTime.now().subtract(const Duration(days: 84));
    return kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).get(),
          builder: (context, snapshot) => _buildLineChartContent(context, snapshot, twelveWeeksAgo),
        )
      : StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('orders').where('restaurantId', isEqualTo: restaurantId).snapshots(),
          builder: (context, snapshot) => _buildLineChartContent(context, snapshot, twelveWeeksAgo),
        );
  }

  Widget _buildLineChartContent(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot, DateTime twelveWeeksAgo) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return SizedBox(height: MediaQuery.of(context).size.width < 600 ? 280 : 350, child: const Center(child: CircularProgressIndicator()));
    }
    if (snapshot.hasError) {
      return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.red)));
    }
    
    Map<int, double> weeklyRevenue = { for (int i = 0; i < 12; i++) i: 0 };
    if (snapshot.hasData) {
      for (var doc in snapshot.data!.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] == 'cancelled') continue;
        if (data['createdAt'] == null) continue;
        
        final date = (data['createdAt'] as Timestamp).toDate();
        // In-memory filter for twelve weeks ago
        if (date.isBefore(twelveWeeksAgo)) continue;
        
        final daysDiff = DateTime.now().difference(date).inDays;
        final weekIndex = 11 - (daysDiff / 7).floor();
        if (weekIndex >= 0 && weekIndex < 12) {
          weeklyRevenue[weekIndex] = (weeklyRevenue[weekIndex] ?? 0) + (data['totalAmount'] ?? 0);
        }
      }
    }
    final maxRevenue = weeklyRevenue.values.fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      height: MediaQuery.of(context).size.width < 600 ? 280 : 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF141615), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        children: [
          const Text("Weekly Revenue Trend (Last 12 Weeks)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                backgroundColor: const Color(0xFF141615),
                maxY: maxRevenue > 0 ? maxRevenue * 1.2 : 100,
                gridData: FlGridData(
                  show: true, 
                  drawVerticalLine: false, 
                  horizontalInterval: maxRevenue > 0 ? maxRevenue / 4 : 25,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, meta) {
                        if (v >= 1000) return Text('₹${(v / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 8, color: Colors.white54));
                        return Text('₹${v.toStringAsFixed(0)}', style: const TextStyle(fontSize: 8, color: Colors.white54));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: _buildLineChartTitle)),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF141615),
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem("₹${s.y.toStringAsFixed(0)}", const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold))).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: weeklyRevenue.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                    isCurved: true,
                    color: const Color(0xFFFCDD22),
                    barWidth: 3,
                    belowBarData: BarAreaData(show: true, color: const Color(0xFFFCDD22).withOpacity(0.1)),
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChartTitle(double value, TitleMeta meta) {
    if (value.toInt() == 11) return const Text("Now", style: TextStyle(color: Color(0xFFFCDD22), fontSize: 10, fontWeight: FontWeight.bold));
    if (value.toInt() == 0) return const Text("-12w", style: TextStyle(color: Colors.white54, fontSize: 10));
    if (value.toInt() == 5) return const Text("-6w", style: TextStyle(color: Colors.white54, fontSize: 10));
    return const SizedBox.shrink();
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFFCDD22).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: const Color(0xFFFCDD22), size: 18),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: const Color(0xFFFCDD22).withOpacity(0.2), thickness: 1.5)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? subtitle, Color? subtitleColor}) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final themeYellow = const Color(0xFFFCDD22);

    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeYellow.withOpacity(0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center, // Center vertically
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: subtitleColor ?? themeYellow, size: isMobile ? 20 : 24),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(title, style: TextStyle(color: Colors.white70, fontSize: isMobile ? 9 : 10, fontWeight: FontWeight.bold))),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold, color: subtitleColor ?? themeYellow))),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            FittedBox(fit: BoxFit.scaleDown, child: Text(subtitle, style: TextStyle(color: subtitleColor ?? Colors.grey, fontSize: isMobile ? 9 : 10))),
          ]
        ],
      ),
    );
  }

  void _showOrderDetailDialog(String title, List<QueryDocumentSnapshot> orders) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
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
                        decoration: BoxDecoration(color: const Color(0xFFFCDD22).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.receipt_long, color: Color(0xFFFCDD22), size: 20),
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
                        icon: const Icon(Icons.print, color: Color(0xFFFCDD22), size: 18),
                        onPressed: () => ReportService.printOrderReceipt(data, orders[index].id),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildTrendingMenuSection(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    
    Map<String, int> itemCounts = {};
    for (var doc in snapshot.data!.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final items = data['items'] as List? ?? [];
      for (var it in items) {
        final name = it['name'] ?? 'Unknown';
        itemCounts[name] = (itemCounts[name] ?? 0) + ((it['quantity'] ?? 1) as num).toInt();
      }
    }

    final sortedItems = itemCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final topItems = sortedItems.take(6).toList();
    final maxCount = topItems.isNotEmpty ? topItems.first.value : 1;

    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: Color(0xFFFCDD22), size: 20),
              const SizedBox(width: 8),
              const Text("Top Trending Menu Items", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          if (topItems.isEmpty)
            const Center(child: Text("No trending items found", style: TextStyle(color: Colors.white24)))
          else
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: topItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final item = topItems[index];
                  final progress = item.value / maxCount;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(item.key, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                          Text("${item.value} Sold", style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white.withOpacity(0.05),
                          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFFFCDD22).withOpacity(0.8)),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryColumnChart(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    
    Map<String, double> catRevenue = {};
    for (var doc in snapshot.data!.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final items = data['items'] as List? ?? [];
      for (var it in items) {
        final cat = it['category'] ?? 'General';
        catRevenue[cat] = (catRevenue[cat] ?? 0) + ((it['price'] ?? 0) * (it['quantity'] ?? 1));
      }
    }

    final topCats = catRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final displayCats = topCats.take(6).toList();
    final maxRevenue = displayCats.isNotEmpty ? displayCats.first.value : 100;

    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart, color: Color(0xFFFCDD22), size: 20),
              const SizedBox(width: 8),
              const Text("Category Sales Column Chart", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          if (displayCats.isEmpty)
             const Center(child: Text("No category data found", style: TextStyle(color: Colors.white24)))
          else
            Expanded(
              child: BarChart(
                BarChartData(
                  backgroundColor: const Color(0xFF141615),
                  maxY: maxRevenue * 1.2,
                  barGroups: List.generate(displayCats.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: displayCats[i].value,
                          width: 25,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          color: Colors.primaries[i % Colors.primaries.length].withOpacity(0.8),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, meta) {
                          if (v >= 1000) return Text('₹${(v / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 8, color: Colors.white54));
                          return Text('₹${v.toStringAsFixed(0)}', style: const TextStyle(fontSize: 8, color: Colors.white54));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= displayCats.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(displayCats[i].key, style: const TextStyle(fontSize: 8, color: Colors.white54)),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withOpacity(0.05))),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
