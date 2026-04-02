import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/urban_piper_service.dart';

class OnlineOrdersScreen extends StatefulWidget {
  final bool isTab;
  const OnlineOrdersScreen({super.key, this.isTab = false});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UrbanPiperService _upService = UrbanPiperService();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;

    if (restaurantId == null) {
      return const Scaffold(
        backgroundColor: const Color(0xFF141615),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22))),
      );
    }

    Widget body = kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: _firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .where('orderSource', isEqualTo: 'urbanpiper')
              .get(),
          builder: (context, snapshot) => _buildOnlineOrdersList(context, snapshot),
        )
      : StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .where('orderSource', isEqualTo: 'urbanpiper')
              .snapshots(),
          builder: (context, snapshot) => _buildOnlineOrdersList(context, snapshot),
        );

    if (widget.isTab) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFFFCDD22)),
                  onPressed: () => setState(() {}),
                  tooltip: "Refresh Online Orders",
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      appBar: AppBar(
        title: const Text("ZOMATO / SWIGGY ORDERS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF141615),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFFCDD22)),
            onPressed: () => setState(() {}),
            tooltip: "Refresh Online Orders",
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildOnlineOrdersList(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
    if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

    final orders = (snapshot.data?.docs ?? []).toList();
    // Sort in-memory to avoid needing a composite index
    orders.sort((a, b) {
      final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
      final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
      return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(aTime?.millisecondsSinceEpoch ?? 0);
    });

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(Icons.cloud_off, size: 64, color: Colors.white.withOpacity(0.1)),
             const SizedBox(height: 16),
             const Text("No online orders yet.", style: TextStyle(color: Colors.white54)),
             const Text("Orders from Zomato/Swiggy will appear here.", style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final doc = orders[index];
        final data = doc.data() as Map<String, dynamic>;
        return _buildOrderCard(doc.id, data);
      },
    );
  }

  Widget _buildOrderCard(String id, Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    final items = data['items'] as List? ?? [];
    final total = (data['totalAmount'] ?? 0).toDouble();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final channel = data['channel'] ?? 'Zomato'; // e.g. Zomato, Swiggy

    Color statusColor = Colors.orange;
    if (status == 'acknowledged' || status == 'confirmed') statusColor = Colors.blue;
    if (status == 'ready') statusColor = Colors.green;
    if (status == 'cancelled') statusColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: channel.toString().toLowerCase() == 'zomato' ? Colors.red.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(channel.toString().toUpperCase(), 
                              style: TextStyle(color: channel.toString().toLowerCase() == 'zomato' ? Colors.redAccent : Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text("#${data['externalId'] ?? id.substring(0, 5)}", 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(DateFormat('hh:mm a').format(createdAt), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(status.toString().toUpperCase(), 
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          // Items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: items.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${i['quantity']}x ${i['name']}", style: const TextStyle(color: Colors.white70)),
                    Text("₹${i['price']}", style: const TextStyle(color: Colors.white38)),
                  ],
                ),
              )).toList(),
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          // Footer
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total: ₹${total.toStringAsFixed(2)}", 
                  style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    if (status == 'pending')
                      ElevatedButton(
                        onPressed: () => _updateStatus(id, 'acknowledged', totalAmount: total),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                        child: const Text("ACCEPT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    if (status == 'acknowledged' || status == 'confirmed')
                      ElevatedButton(
                        onPressed: () => _updateStatus(id, 'food_ready'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text("MARK READY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    const SizedBox(width: 8),
                    if (status != 'cancelled')
                      IconButton(
                        icon: const Icon(Icons.print, color: Color(0xFFFCDD22), size: 20),
                        onPressed: () {
                          // TODO: Call ReportService.printOnlineOrder(data);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateStatus(String orderId, String newStatus, {double? totalAmount}) async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    
    // 1. Update Firestore locally in a batch/transaction to ensure consistency
    final batch = _firestore.batch();
    final orderRef = _firestore.collection('orders').doc(orderId);
    
    batch.update(orderRef, {'status': newStatus});

    // If accepted, update daily collection
    if (newStatus == 'acknowledged' && totalAmount != null && restaurantId != null) {
      final collectionId = "${restaurantId}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}";
      final collectionRef = _firestore.collection('daily_collections').doc(collectionId);
      
      batch.set(collectionRef, {
        'netCollection': FieldValue.increment(totalAmount),
        'onlineCollection': FieldValue.increment(totalAmount),
        'billCount': FieldValue.increment(1),
        'onlineCount': FieldValue.increment(1),
        'restaurantId': restaurantId,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    
    await batch.commit();
    
    // 2. Notify UrbanPiper (Phase 3)
    // _upService.updateOrderStatus(orderId, newStatus);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Order status updated to $newStatus")));
    }
  }
}
