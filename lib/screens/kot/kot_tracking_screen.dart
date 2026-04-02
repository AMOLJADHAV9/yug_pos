import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
    final auth = context.watch<AuthService>();
    final restaurantId = auth.restaurantId;

    if (restaurantId == null) {
      return const Scaffold(
        backgroundColor: const Color(0xFF141615),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141615),
        elevation: 0,
        title: const Text('Active KOTs', style: TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Color(0xFFFCDD22)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: "Refresh KOTs",
          ),
        ],
      ),
      body: kIsWeb 
        ? FutureBuilder<QuerySnapshot>(
            future: firestore
                .collection('kots')
                .where('restaurantId', isEqualTo: restaurantId)
                .get(),
            builder: (context, snapshot) => _buildKotList(context, snapshot),
          )
        : StreamBuilder<QuerySnapshot>(
            stream: firestore
                .collection('kots')
                .where('restaurantId', isEqualTo: restaurantId)
                .snapshots(),
            builder: (context, snapshot) => _buildKotList(context, snapshot),
          ),
    );
  }

  Widget _buildKotList(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
    if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)));
    
    final kots = snapshot.data?.docs.toList() ?? [];
    kots.sort((a, b) {
      final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
      final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
      return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
    });
    if (kots.isEmpty) return const Center(child: Text("All KOTs are clear!", style: TextStyle(color: Colors.white54)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: kots.length,
      itemBuilder: (context, index) {
        final kotDoc = kots[index];
        final data = kotDoc.data() as Map<String, dynamic>;
        final items = data['items'] as List;
        final status = data['status'] ?? 'Pending';
        final orderId = data['orderId'];

              if (status == 'Served' || status == 'Done') return const SizedBox();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141615),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCDD22).withOpacity(0.1)),
                ),
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
                                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFFCDD22))),
                              Text("Table: ${data['tableName'] ?? 'N/A'}", style: const TextStyle(color: Colors.white70)),
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
                      Divider(color: Colors.white.withOpacity(0.05)),
                      ...items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Text('${item['quantity']}x', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFCDD22))),
                              const SizedBox(width: 8),
                              Expanded(child: Text(item['name'], style: const TextStyle(color: Colors.white))),
                            ],
                          ),
                        );
                      }),
                      Divider(color: Colors.white.withOpacity(0.05)),
                    ],
                  ),
                ),
              );
      },
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
