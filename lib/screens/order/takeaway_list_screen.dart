import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../widgets/takeaway_order_dialog.dart';

class TakeawayListScreen extends StatefulWidget {
  const TakeawayListScreen({super.key});

  @override
  State<TakeawayListScreen> createState() => _TakeawayListScreenState();
}

class _TakeawayListScreenState extends State<TakeawayListScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restaurantId = context.watch<AuthService>().restaurantId;

    if (restaurantId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE7FF12))),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Takeaway & Delivery", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE7FF12),
          labelColor: const Color(0xFFE7FF12),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: "TAKEAWAY"),
            Tab(text: "DELIVERY"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFE7FF12)),
            onPressed: () => setState(() {}),
            tooltip: "Refresh Orders",
          ),
          IconButton(
            icon: const Icon(Icons.shopping_bag, color: Color(0xFFE7FF12)),
            onPressed: () => showDialog(context: context, builder: (context) => TakeawayOrderDialog(orderType: 'takeaway')),
            tooltip: "New Takeaway",
          ),
          IconButton(
            icon: const Icon(Icons.delivery_dining, color: Color(0xFFE7FF12)),
            onPressed: () => showDialog(context: context, builder: (context) => TakeawayOrderDialog(orderType: 'delivery')),
            tooltip: "New Delivery",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList(restaurantId, 'takeaway'),
          _buildOrdersList(restaurantId, 'delivery'),
        ],
      ),
    );
  }

  Widget _buildOrdersList(String restaurantId, String orderType) {
    return kIsWeb 
      ? FutureBuilder<QuerySnapshot>(
          future: _firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .where('orderType', isEqualTo: orderType)
              .orderBy('createdAt', descending: true)
              .get(),
          builder: (context, snapshot) => _buildOrdersListContent(context, snapshot, orderType),
        )
      : StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('orders')
              .where('restaurantId', isEqualTo: restaurantId)
              .where('orderType', isEqualTo: orderType)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) => _buildOrdersListContent(context, snapshot, orderType),
        );
  }

  Widget _buildOrdersListContent(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot, String orderType) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
    
    final orders = snapshot.data?.docs ?? [];
    if (orders.isEmpty) return Center(child: Text("No $orderType orders found", style: const TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final doc = orders[index];
        final data = doc.data() as Map<String, dynamic>;
        
        if (orderType == 'delivery') {
          return _buildDeliveryCard(doc.id, data);
        } else {
          return _buildTakeawayCard(doc.id, data);
        }
      },
    );
  }

  Widget _buildTakeawayCard(String orderId, Map<String, dynamic> data) {
    final bool isDelivered = data['isDelivered'] ?? false;
    final String status = data['takeawayStatus'] ?? (isDelivered ? 'picked_up' : 'pending');
    
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final total = data['totalAmount'] ?? 0.0;

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: status == 'picked_up' ? Colors.green.withOpacity(0.3) : const Color(0xFFE7FF12).withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "${data['customerName'] ?? 'Walk-in'} (${(data['items'] as List?)?.length ?? 0} items)", 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
            const Divider(color: Colors.white10, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Payment: ${data['paymentMethod'] ?? 'Cash'}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text("Total: ₹${total.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
            if (status != 'picked_up') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _advanceTakeawayStatus(orderId, status),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(status == 'pending' ? "MARK READY" : "MARK PICKED UP (BILL)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status == 'pending' ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryCard(String orderId, Map<String, dynamic> data) {
    final bool isDelivered = data['isDelivered'] ?? false;
    final String status = data['deliveryStatus'] ?? (isDelivered ? 'delivered' : 'pending');
    
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final total = data['totalAmount'] ?? 0.0;

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: status == 'delivered' ? Colors.green.withOpacity(0.3) : const Color(0xFFE7FF12).withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "${data['customerName'] ?? 'Walk-in'} (${(data['items'] as List?)?.length ?? 0} items)", 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
            const SizedBox(height: 4),
            Text("Phone: ${data['customerPhone'] ?? 'N/A'}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (data['deliveryAddress'] != null && data['deliveryAddress'].toString().isNotEmpty)
              Text("Address: ${data['deliveryAddress']}", style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w500)),
            if (data['deliveryBoy'] != null && data['deliveryBoy'].toString().isNotEmpty)
              Text("Rider: ${data['deliveryBoy']}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            const Divider(color: Colors.white10, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Payment: ${data['paymentMethod'] ?? 'Cash'}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text("Total: ₹${total.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
            if (status != 'delivered') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _advanceDeliveryStatus(orderId, status),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(
                    status == 'pending' ? "MARK PREPARING" : 
                    status == 'preparing' ? "OUT FOR DELIVERY" : 
                    "MARK DELIVERED (BILL)"
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status == 'pending' ? Colors.orange : status == 'preparing' ? Colors.blue : Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'pending': color = Colors.orange; label = "PENDING"; break;
      case 'ready': color = Colors.blue; label = "READY"; break;
      case 'picked_up': color = Colors.green; label = "PICKED UP"; break;
      case 'preparing': color = Colors.orange; label = "PREPARING"; break;
      case 'out_for_delivery': color = Colors.blue; label = "DISPATCHED"; break;
      case 'delivered': color = Colors.green; label = "DELIVERED"; break;
      default: color = Colors.grey; label = status.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Future<void> _advanceTakeawayStatus(String orderId, String currentStatus) async {
    if (currentStatus == 'pending') {
      await _firestore.collection('orders').doc(orderId).update({'takeawayStatus': 'ready'});
    } else if (currentStatus == 'ready') {
      await _finalizeOrder(orderId, 'picked_up', 'takeawayStatus');
    }
  }

  Future<void> _advanceDeliveryStatus(String orderId, String currentStatus) async {
    if (currentStatus == 'pending') {
      await _firestore.collection('orders').doc(orderId).update({'deliveryStatus': 'preparing'});
    } else if (currentStatus == 'preparing') {
      await _firestore.collection('orders').doc(orderId).update({'deliveryStatus': 'out_for_delivery'});
    } else if (currentStatus == 'out_for_delivery') {
      await _finalizeOrder(orderId, 'delivered', 'deliveryStatus');
    }
  }

  Future<void> _finalizeOrder(String orderId, String finalStatusStr, String statusField) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Finalize Order?", style: TextStyle(color: Colors.white)),
        content: const Text("This will mark the order as complete and add it to today's billing.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirm & Bill")),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final kotsSnap = await _firestore.collection('kots').where('orderId', isEqualTo: orderId).get();

      await _firestore.runTransaction((transaction) async {
        final orderRef = _firestore.collection('orders').doc(orderId);
        final orderSnap = await transaction.get(orderRef);
        
        if (!orderSnap.exists) return;
        final data = orderSnap.data() as Map<String, dynamic>;
        final total = (data['totalAmount'] ?? 0.0).toDouble();
        final restaurantId = data['restaurantId'];
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final collectionRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");

        final updateData = <String, dynamic>{
          'isDelivered': true,
          'status': 'billed',
          'billedAt': FieldValue.serverTimestamp(),
        };

        if (statusField == 'takeawayStatus') updateData['takeawayStatus'] = 'picked_up';
        if (statusField == 'deliveryStatus') updateData['deliveryStatus'] = 'delivered';

        transaction.update(orderRef, updateData);

        final isDelivery = statusField == 'deliveryStatus';
        final updates = <String, dynamic>{
          'netCollection': FieldValue.increment(total),
          'grossCollection': FieldValue.increment(total),
          'billCount': FieldValue.increment(1),
          'restaurantId': restaurantId,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        };
        
        if (isDelivery) {
          updates['deliveryCollection'] = FieldValue.increment(total);
          updates['deliveryCount'] = FieldValue.increment(1);
        } else {
          updates['takeawayCollection'] = FieldValue.increment(total);
          updates['takeawayCount'] = FieldValue.increment(1);
        }

        transaction.set(collectionRef, updates, SetOptions(merge: true));

        for (var doc in kotsSnap.docs) {
          transaction.update(doc.reference, {'status': 'Served'});
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order completed and billed!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }
}
