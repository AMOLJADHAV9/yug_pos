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
    final firestore = FirebaseFirestore.instance;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfYesterday = DateTime(yesterday.year, yesterday.month, yesterday.day);

    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Administration Overview", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          // ── TODAY ──────────────────────────────────────────────────────
            _buildSectionHeader("Today's Performance", Icons.today, Colors.orange),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: firestore.collection('orders')
                  .where('restaurantId', isEqualTo: restaurantId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 12)));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                double todayRevenue = 0;
                double yesterdayRevenue = 0;
                int completedOrders = 0;
                int cancelledOrders = 0;
                
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['createdAt'] == null) continue;
                    
                    final createdAt = (data['createdAt'] as Timestamp).toDate();
                    // In-memory filter for Today/Yesterday
                    if (createdAt.isBefore(startOfYesterday)) continue;
                    
                    final amount = (data['totalAmount'] ?? 0).toDouble();
                    final status = data['status'] ?? 'open';
                    
                    if (createdAt.isAfter(startOfDay)) {
                      if (status == 'cancelled') {
                        cancelledOrders++;
                      } else {
                        todayRevenue += amount;
                        if (status == 'billed') completedOrders++;
                      }
                    } else if (createdAt.isAfter(startOfYesterday) && createdAt.isBefore(startOfDay)) {
                      if (status != 'cancelled') {
                        yesterdayRevenue += amount;
                      }
                    }
                  }
                }

                String revenueTrend = "";
                Color trendColor = Colors.grey;
                if (yesterdayRevenue > 0) {
                  double growth = ((todayRevenue - yesterdayRevenue) / yesterdayRevenue) * 100;
                  revenueTrend = "${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}% vs yesterday";
                  trendColor = growth >= 0 ? Colors.green : Colors.red;
                }

                final width = MediaQuery.of(context).size.width;
                // Force 4 columns on most screens
                int crossAxis = width > 500 ? 5 : (width > 400 ? 4 : 2);

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxis,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  // Taller aspect ratio ensures enough height for 3 lines of text
                  childAspectRatio: width > 1200 ? 1.8 : (width > 800 ? 1.3 : 0.85), 
                  children: [
                    _buildStatCard(
                      "Today's Sales", 
                      "₹${todayRevenue.toStringAsFixed(2)}", 
                      Icons.currency_rupee, 
                      Colors.green,
                      subtitle: revenueTrend,
                      subtitleColor: trendColor,
                    ),
                    _buildStatCard("Billed Orders", completedOrders.toString(), Icons.check_circle, Colors.blue),
                    _buildStatCard("Cancelled Today", cancelledOrders.toString(), Icons.block, Colors.red),
                    _buildActiveTablesCard(firestore, restaurantId),
                    _buildPendingKotsCard(firestore, restaurantId),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
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
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: color.withOpacity(0.2), thickness: 1.5)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? subtitle, Color? subtitleColor}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.12), color.withOpacity(0.04)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(title,
                      style: TextStyle(color: color.withOpacity(0.75), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.1)),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.withOpacity(0.9))),
                  ),
                  if (subtitle != null) ...[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(subtitle,
                        style: TextStyle(color: subtitleColor ?? Colors.grey, fontSize: 8, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
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
        return _buildStatCard("Occupied Tables", count.toString(), Icons.table_bar, Colors.orange);
      },
    );
  }

  Widget _buildPendingKotsCard(FirebaseFirestore firestore, String? restaurantId) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('kots')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('status', whereIn: ['Pending', 'Preparing'])
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildStatCard("Pending KOTs", count.toString(), Icons.timer, Colors.red);
      },
    );
  }
}

