import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../models/table_model.dart';
import '../../utils/debouncer.dart';
import 'menu_screen.dart';

class OrderSummaryScreen extends StatefulWidget {
  final TableModel table;
  final String orderId;

  const OrderSummaryScreen({super.key, required this.table, required this.orderId});

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _debouncer = Debouncer(milliseconds: 1000);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text('Table ${widget.table.name} Order', style: const TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Color(0xFFE7FF12)),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('orders').doc(widget.orderId).snapshots(),
            builder: (context, snapshot) {
              final status = snapshot.hasData && snapshot.data!.exists 
                  ? (snapshot.data!.data() as Map<String, dynamic>)['status'] 
                  : 'active';
              
              if (status == 'bill_requested') {
                return const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(child: Text('Bill Requested', style: TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold))),
                );
              }

              return TextButton.icon(
                onPressed: () => _debouncer.run(() => _requestBill(context)),
                icon: const Icon(Icons.receipt_long, color: Color(0xFFE7FF12)),
                label: const Text('Request Bill', style: TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold)),
              );
            }
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('orders').doc(widget.orderId)
            .collection('items')
            .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final items = snapshot.data!.docs.toList();
          // Sort in memory to avoid requiring a composite index
          items.sort((a, b) => (a['status'] ?? '').toString().compareTo((b['status'] ?? '').toString()));
          
          if (items.isEmpty) return const Center(child: Text('No items yet'));

          double totalAmount = 0;
          for (var doc in items) {
            totalAmount += ((doc.data() as Map<String,dynamic>)['totalPrice'] ?? 0).toDouble();
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final data = items[index].data() as Map<String, dynamic>;
                    return _buildOrderItemCard(data);
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -5))]
                ),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('₹${totalAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFE7FF12))),
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => MenuScreen(table: widget.table)));
        },
        backgroundColor: const Color(0xFFE7FF12),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add More', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildOrderItemCard(Map<String, dynamic> data) {
    final status = data['status'] ?? 'Pending';
    Color statusColor;
    switch (status) {
      case 'Preparing':
        statusColor = Colors.orange;
        break;
      case 'Done':
        statusColor = Colors.green;
        break;
      default: // Pending
        statusColor = Colors.blue;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            const Text('x', style: TextStyle(color: Colors.white38, fontSize: 14)),
            Text('${data['quantity']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE7FF12), fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(child: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white))),
          ],
        ),
        subtitle: data['specialInstructions'] != null && data['specialInstructions'].toString().isNotEmpty
            ? Text('Note: ${data['specialInstructions']}', style: const TextStyle(color: Colors.redAccent))
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('₹${data['totalPrice'].toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _requestBill(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Request Bill?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFE7FF12).withOpacity(0.1))),
        content: const Text('This will notify the cashier and lock the order from adding new items.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), 
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold))
          ),
        ],
      )
    );

    if (confirm == true) {
      await _firestore.collection('orders').doc(widget.orderId).update({
        'status': 'bill_requested',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bill requested successfully.')));
      }
    }
  }
}
