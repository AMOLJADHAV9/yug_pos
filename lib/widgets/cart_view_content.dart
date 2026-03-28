import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../providers/cart_provider.dart';

class CartViewContent extends StatefulWidget {
  final bool isBottomSheet;
  const CartViewContent({super.key, this.isBottomSheet = false});

  @override
  State<CartViewContent> createState() => _CartViewContentState();
}

class _CartViewContentState extends State<CartViewContent> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: widget.isBottomSheet ? const BorderRadius.vertical(top: Radius.circular(24)) : null,
      ),
      padding: const EdgeInsets.only(top: 16),
      child: SafeArea(
        child: Column(
          children: [
            if (widget.isBottomSheet)
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
              ),
            const Text('Your Order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Expanded(
              child: Consumer<CartProvider>(
                builder: (context, cart, child) {
                  if (cart.items.isEmpty) {
                    return const Center(child: Text('Cart is empty'));
                  }
                  return ListView.builder(
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final cartItem = cart.items[index];
                      return Dismissible(
                        key: ValueKey('${cartItem.item.id}_${cartItem.specialInstructions}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          cart.removeItem(cartItem);
                        },
                        child: ListTile(
                          isThreeLine: cartItem.specialInstructions.isNotEmpty,
                          title: Text(cartItem.item.name, 
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: cartItem.specialInstructions.isNotEmpty
                              ? Text('Note: ${cartItem.specialInstructions}', 
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.white60),
                                    onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity - 1),
                                  ),
                                  const SizedBox(width: 4),
                                  Text('${cartItem.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFFE7FF12)),
                                    onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity + 1),
                                  ),
                                ],
                              ),
                              Text('₹${cartItem.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE7FF12))),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            Consumer<CartProvider>(
              builder: (context, cart, child) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('₹${cart.totalAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFE7FF12))),
                    ],
                  ),
                );
              }
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: Consumer<CartProvider>(
                  builder: (context, cart, child) {
                    return ElevatedButton(
                      onPressed: cart.items.isEmpty || _isSubmitting ? null : () => _placeOrder(cart, context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFE7FF12),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Text('PLACE ORDER (SEND KOT)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    );
                  }
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _placeOrder(CartProvider cart, BuildContext context) async {
    if (cart.tableId == null) return;
    setState(() => _isSubmitting = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      final tableRef = firestore.collection('tables').doc(cart.tableId);
      final tableDoc = await tableRef.get();
      
      String orderId;
      final cartTotal = cart.totalAmount;
      final cartItemsSummary = cart.items.map((i) => {
        'id': i.item.id,
        'name': i.item.name,
        'price': i.item.price,
        'quantity': i.quantity,
        'category': i.item.category,
      }).toList();

      final auth = context.read<AuthService>();
      final restaurantId = auth.restaurantId;
      final restaurantName = auth.restaurantName ?? "LDMA POS";
      final cashierName = auth.userName ?? 'Cashier';
      final customerName = cart.customerName ?? 'Walk-in';
      final customerPhone = cart.customerPhone ?? '';
      final waiterName = cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter';

      if (tableDoc.exists && tableDoc.data()?['currentOrderId'] != null) {
        orderId = tableDoc.data()!['currentOrderId'];
        final orderRef = firestore.collection('orders').doc(orderId);
        batch.update(orderRef, {
          'totalAmount': FieldValue.increment(cartTotal),
          'items': FieldValue.arrayUnion(cartItemsSummary),
        });
      } else {
        final orderRef = firestore.collection('orders').doc();
        orderId = orderRef.id;
        batch.set(orderRef, {
          'tableId': cart.tableId,
          'tableName': (tableDoc.data() as Map<String, dynamic>)['name'] ?? 'Unknown',
          'waiterName': waiterName,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'cashierName': cashierName,
          'status': 'active',
          'restaurantId': restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
          'totalAmount': cartTotal,
          'items': cartItemsSummary,
        });
        batch.update(tableRef, {
          'status': 'occupied',
          'currentOrderId': orderId,
        });
      }

      final kotRef = firestore.collection('kots').doc();
      final kotId = kotRef.id;
      final kotNumber = kotId.substring(0, 6).toUpperCase();

      final kotItems = cart.items.map((cartItem) => {
        'menuItemId': cartItem.item.id,
        'name': cartItem.item.name,
        'quantity': cartItem.quantity,
        'price': cartItem.item.price,
        'specialInstructions': cartItem.specialInstructions,
      }).toList();

      batch.set(kotRef, {
        'orderId': orderId,
        'tableId': cart.tableId,
        'tableName': (tableDoc.data() as Map<String, dynamic>)['name'] ?? 'Unknown',
        'customerName': customerName,
        'customerPhone': customerPhone,
        'waiterName': waiterName,
        'cashierName': cashierName,
        'status': 'Pending',
        'restaurantId': restaurantId,
        'items': kotItems,
        'createdAt': FieldValue.serverTimestamp(),
        'kotNumber': kotNumber,
      });

      final itemsRef = firestore.collection('orders').doc(orderId).collection('items');
      for (var cartItem in cart.items) {
        final newItemRef = itemsRef.doc();
        batch.set(newItemRef, {
          'kotId': kotId,
          'menuItemId': cartItem.item.id,
          'name': cartItem.item.name,
          'quantity': cartItem.quantity,
          'price': cartItem.item.price,
          'totalPrice': cartItem.totalPrice,
          'specialInstructions': cartItem.specialInstructions,
          'restaurantId': restaurantId,
          'status': 'Pending',
        });
      }

      await batch.commit();
      
      // Auto-Print KOT for Waiter
      final kotData = {
        'tableName': tableDoc.exists ? (tableDoc.data() as Map<String, dynamic>)['name'] : 'Unknown',
        'customerName': customerName,
        'customerPhone': customerPhone,
        'waiterName': waiterName,
        'cashierName': cashierName,
        'kotNumber': kotNumber,
        'createdAt': DateTime.now(),
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'price': i.item.price,
        }).toList(),
      };
      await ReportService.printKOTReceipt(kotData, orderId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order Placed! KOT: ${kotId.substring(0, 6).toUpperCase()}'),
          backgroundColor: Colors.green,
        ));
        cart.clearCart();
        if (widget.isBottomSheet) {
           Navigator.pop(context);
        }
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to place order: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}
