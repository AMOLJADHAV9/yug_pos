import 'package:flutter/material.dart';
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

class _TakeawayListScreenState extends State<TakeawayListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final restaurantId = context.read<AuthService>().restaurantId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Takeaway Orders", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart, color: Color(0xFFE7FF12)),
            onPressed: () => showDialog(context: context, builder: (context) => const TakeawayOrderDialog()),
            tooltip: "New Takeaway",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('orders')
            .where('restaurantId', isEqualTo: restaurantId)
            .where('orderType', isEqualTo: 'takeaway')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          
          final orders = snapshot.data?.docs ?? [];
          if (orders.isEmpty) return const Center(child: Text("No takeaway orders found", style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildTakeawayCard(doc.id, data);
            },
          );
        },
      ),
    );
  }

  Widget _buildTakeawayCard(String orderId, Map<String, dynamic> data) {
    final bool isDelivered = data['isDelivered'] ?? false;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final total = data['totalAmount'] ?? 0.0;

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDelivered ? Colors.green.withOpacity(0.3) : const Color(0xFFE7FF12).withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data['customerName'] ?? 'Walk-in', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDelivered ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isDelivered ? "DELIVERED" : "PENDING", 
                    style: TextStyle(color: isDelivered ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text("Phone: ${data['customerPhone'] ?? 'N/A'}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (data['deliveryAddress'] != null && data['deliveryAddress'].toString().isNotEmpty)
              Text("Address: ${data['deliveryAddress']}", style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
            const SizedBox(height: 12),
            if (!isDelivered)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _markAsDelivered(orderId),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text("MARK DELIVERED"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsDelivered(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Mark as Delivered?", style: TextStyle(color: Colors.white)),
        content: const Text("Has this order been picked up or delivered?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Delivered")),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Fetch association KOTs before starting the transaction
        final kotsSnap = await _firestore.collection('kots')
            .where('orderId', isEqualTo: orderId)
            .get();

        await _firestore.runTransaction((transaction) async {
          final orderRef = _firestore.collection('orders').doc(orderId);
          final orderSnap = await transaction.get(orderRef);
          
          if (!orderSnap.exists) return;
          final data = orderSnap.data() as Map<String, dynamic>;
          final total = (data['totalAmount'] ?? 0.0).toDouble();
          final restaurantId = data['restaurantId'];
          final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
          final collectionRef = _firestore.collection('daily_collections').doc("${restaurantId}_$today");

          transaction.update(orderRef, {
            'isDelivered': true,
            'status': 'billed', // Automatically close the order when delivered
            'billedAt': FieldValue.serverTimestamp(),
          });

          // Update daily collections
          transaction.set(collectionRef, {
            'netCollection': FieldValue.increment(total),
            'grossCollection': FieldValue.increment(total),
            'takeawayCollection': FieldValue.increment(total),
            'billCount': FieldValue.increment(1),
            'takeawayCount': FieldValue.increment(1),
            'restaurantId': restaurantId,
            'lastUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // Mark KOTs as Served
          for (var doc in kotsSnap.docs) {
            transaction.update(doc.reference, {'status': 'Served'});
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order marked as delivered!")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
        }
      }
    }
  }
}
