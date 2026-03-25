import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/debouncer.dart';

class KotTrackingScreen extends StatefulWidget {
  const KotTrackingScreen({super.key});

  @override
  State<KotTrackingScreen> createState() => _KotTrackingScreenState();
}

class _KotTrackingScreenState extends State<KotTrackingScreen> {
  final _debouncer = Debouncer(milliseconds: 1000);

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return Scaffold(
      appBar: AppBar(title: const Text('Active KOTs')),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('kots')
            .where('restaurantId', isEqualTo: restaurantId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final kots = snapshot.data!.docs;
          if (kots.isEmpty) return const Center(child: Text("All KOTs are clear!"));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: kots.length,
            itemBuilder: (context, index) {
              final data = kots[index].data() as Map<String, dynamic>;
              final items = data['items'] as List;
              final status = data['status'] ?? 'Pending';
              final orderId = data['orderId'];

              if (status == 'Served') return const SizedBox();

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("KOT #${kots[index].id.substring(0, 6).toUpperCase()}", 
                                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              Text("Table: ${data['tableName'] ?? 'N/A'}", style: TextStyle(color: Colors.grey[700])),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => _debouncer.run(() => _deleteKot(kots[index].id)),
                                tooltip: "Delete KOT",
                              ),
                              IconButton(
                                icon: const Icon(Icons.block, color: Colors.orange, size: 20),
                                onPressed: () => _debouncer.run(() => _cancelOrder(orderId, data['tableId'])),
                                tooltip: "Cancel Entire Order",
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      ...items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Text('${item['quantity']}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(item['name'])),
                            ],
                          ),
                        );
                      }),
                      const Divider(),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteKot(String id) async {
    // Basic deletion
    await FirebaseFirestore.instance.collection('kots').doc(id).delete();
  }

  Future<void> _cancelOrder(String? orderId, String? tableId) async {
    if (orderId == null || tableId == null) return;
    
    // Batch update order and table
    final batch = FirebaseFirestore.instance.batch();
    final orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
    final tableRef = FirebaseFirestore.instance.collection('tables').doc(tableId);

    batch.update(orderRef, {
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });

    batch.update(tableRef, {
      'status': 'available',
      'currentOrderId': null,
    });

    await batch.commit();
  }
}
