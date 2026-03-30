import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../providers/cart_provider.dart';

class CartViewContent extends StatefulWidget {
  final bool isBottomSheet;
  final ScrollController? scrollController;
  const CartViewContent({super.key, this.isBottomSheet = false, this.scrollController});

  @override
  State<CartViewContent> createState() => _CartViewContentState();
}

class _CartViewContentState extends State<CartViewContent> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    
    Widget content = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: widget.isBottomSheet ? const BorderRadius.vertical(top: Radius.circular(24)) : null,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- PERSISTENT HEADER (Always at the top of the scrollable) ---
            if (widget.isBottomSheet)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                child: Column(
                  children: [
                    Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: const Color(0xFFE7FF12).withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.shopping_cart, color: Color(0xFFE7FF12), size: 16),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("YOUR ORDER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1, color: Colors.white60)),
                                Text("${cart.totalItems} Items", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFE7FF12), borderRadius: BorderRadius.circular(10)),
                          child: Text("₹${cart.totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            if (!widget.isBottomSheet) ...[
               const SizedBox(height: 16),
               const Text('Your Order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
               const SizedBox(height: 16),
            ],
            
            if (cart.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('Cart is empty', style: TextStyle(color: Colors.white54))),
              )
            else ...[
              const Divider(color: Colors.white10, height: 1),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
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
                    onDismissed: (_) => cart.removeItem(cartItem),
                    child: ListTile(
                      title: Text(cartItem.item.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13), maxLines: 1),
                      subtitle: cartItem.specialInstructions.isNotEmpty ? Text(cartItem.specialInstructions, style: const TextStyle(color: Colors.redAccent, fontSize: 11), maxLines: 1) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, constraints: const BoxConstraints(),
                            icon: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.white60),
                            onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity - 1),
                          ),
                          const SizedBox(width: 8),
                          Text('${cartItem.quantity}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          const SizedBox(width: 8),
                          IconButton(
                            padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, constraints: const BoxConstraints(),
                            icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFFE7FF12)),
                            onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity + 1),
                          ),
                          const SizedBox(width: 12),
                          Text('₹${cartItem.totalPrice.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const Divider(color: Colors.white10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      // --- CLEAR BUTTON ---
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => cart.clearCart(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.redAccent.withOpacity(0.5), width: 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('CLEAR', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // --- CLEAR BUTTON ---
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => cart.clearCart(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Colors.white12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('CLEAR', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // --- KOT BUTTON ---
                      Expanded(
                        flex: 3,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : () => _placeOrder(cart, context, printBill: false),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.white10,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
                          ),
                          child: _isSubmitting 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('KOT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      // --- BILL BUTTON (Only for non-waiters) ---
                      if (context.watch<AuthService>().role != UserRole.waiter) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : () => _placeOrder(cart, context, printBill: true),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: const Color(0xFFE7FF12),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isSubmitting 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                : const Text('BILL', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
            ],
          ],
        ),
      ),
    );

    if (widget.isBottomSheet && widget.scrollController != null) {
      return SingleChildScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(), // ENSURE DRAGGABILITY
        child: content,
      );
    }
    return content;
  }

  Future<void> _placeOrder(CartProvider cart, BuildContext context, {bool printBill = false}) async {
    final isDineIn = cart.orderType == OrderType.dineIn;
    if (isDineIn && cart.tableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a table for Dine-In orders")));
      return;
    }
    
    setState(() => _isSubmitting = true);
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    try {
      String? tableName;
      Map<String, dynamic>? tableData;
      
      if (isDineIn && cart.tableId != null) {
        final tableRef = firestore.collection('tables').doc(cart.tableId);
        final tableDoc = await tableRef.get();
        if (tableDoc.exists) {
          tableData = tableDoc.data() as Map<String, dynamic>;
          tableName = tableData['name'];
        }
      } else {
        tableName = cart.orderType == OrderType.takeaway ? "TAKEAWAY" : "DELIVERY";
      }

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
      final customerName = cart.customerName ?? 'Walk-in';
      final waiterName = cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter';

      // Check if we already have an active order for this table (Dine-In only)
      if (isDineIn && tableData != null && tableData['currentOrderId'] != null) {
        orderId = tableData['currentOrderId'];
        final orderRef = firestore.collection('orders').doc(orderId);
        batch.update(orderRef, {
          'totalAmount': FieldValue.increment(cartTotal),
          'items': FieldValue.arrayUnion(cartItemsSummary),
        });
      } else {
        final orderRef = firestore.collection('orders').doc();
        orderId = orderRef.id;
        batch.set(orderRef, {
          'tableId': isDineIn ? cart.tableId : null,
          'tableName': tableName ?? 'Unknown',
          'orderType': cart.orderType.name,
          'waiterName': waiterName,
          'customerName': customerName,
          'status': 'active',
          'restaurantId': restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
          'totalAmount': cartTotal,
          'items': cartItemsSummary,
        });
        
        if (isDineIn && cart.tableId != null) {
          batch.update(firestore.collection('tables').doc(cart.tableId), {
            'status': 'occupied',
            'currentOrderId': orderId,
          });
        }
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
        'tableId': isDineIn ? cart.tableId : null,
        'tableName': tableName ?? 'Unknown',
        'orderType': cart.orderType.name,
        'customerName': customerName,
        'waiterName': waiterName,
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
      
      // Fetch cashier name for receipt
      final cashierName = auth.userName ?? 'Staff';

      // Auto-Print KOT for Waiter
      final kotData = {
        'tableName': tableName ?? 'Unknown',
        'customerName': customerName,
        'waiterName': waiterName,
        'cashierName': cashierName,
        'kotNumber': kotNumber,
        'createdAt': Timestamp.now(),
        'totalAmount': cart.totalAmount, // Added for receipt printing
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'price': i.item.price,
        }).toList(),
      };
      await ReportService.printKOTReceipt(kotData, orderId);
      
      // If BILL is pressed, print the Premium Final Bill (Invoice Style)
      if (printBill) {
        await ReportService.printFinalBill(
          orderData: kotData,
          orderId: orderId,
          subtotal: cart.totalAmount,
          cgst: 0.0,
          sgst: 0.0,
          total: cart.totalAmount,
          paymentMode: "Cash/Unpaid",
          hotelName: auth.restaurantName ?? "YUG POS",
        );
      }

        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Order Placed! KOT: ${kotId.substring(0, 6).toUpperCase()}'),
            backgroundColor: Colors.green,
          ));
          cart.clearCart();
          
          if (widget.isBottomSheet && Navigator.canPop(context)) {
             Navigator.pop(context);
          }
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
