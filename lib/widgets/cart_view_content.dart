import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../services/usb_printer_service.dart';
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
    final auth = context.watch<AuthService>();
    
    Widget content = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
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
                              decoration: BoxDecoration(color: const Color(0xFFFCDD22).withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.shopping_cart, color: Color(0xFFFCDD22), size: 16),
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
                          decoration: BoxDecoration(color: const Color(0xFFFCDD22), borderRadius: BorderRadius.circular(10)),
                          child: Text("₹${cart.totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, color: const Color(0xFF141615), fontSize: 16)),
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
                            icon: const Icon(Icons.remove_circle_outline, size: 14, color: Colors.white60),
                            onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity - 1),
                          ),
                          const SizedBox(width: 6),
                          Text('${cartItem.quantity}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, constraints: const BoxConstraints(),
                            icon: const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFFFCDD22)),
                            onPressed: () => cart.updateQuantity(cartItem, cartItem.quantity + 1),
                          ),
                          const SizedBox(width: 10),
                          Text('₹${cartItem.totalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const Divider(color: Colors.white10),

              if (widget.isBottomSheet)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Close sheet so the cashier/waiter can continue ordering.
                        if (Navigator.canPop(context)) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                      label: const Text(
                        "ADD ITEMS",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),

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

                    // --- KOT BUTTON ---
                    Expanded(
                      flex: 3,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : () => _placeOrder(cart, context, printBill: false),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('KOT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),

              // --- ADMIN ACTIONS (SETTLE & CLEAR) ---
              if (auth.role == UserRole.admin || auth.role == UserRole.cashier)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      // --- SETTLE BUTTON ---
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : () => _handleAdminSettle(cart, auth),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('SETTLE', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFCDD22),
                            foregroundColor: const Color(0xFF141615),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

  Future<void> _placeOrder(CartProvider cart, BuildContext context, {bool printBill = false, String paymentMode = "Cash"}) async {
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
          'takeawayStatus': cart.orderType == OrderType.takeaway ? 'pending' : null,
          'deliveryStatus': cart.orderType == OrderType.delivery ? 'pending' : null,
          'isDelivered': false,
          'restaurantId': restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
          'totalAmount': cartTotal,
          'totalItems': cart.totalItems,
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

      // Prepare data for printing (needed for both KOT and Final Bill)
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
      final printerService = context.read<UsbPrinterService>();
      final hasUsbPrinter = printerService.selectedDevice != null;

      // Auto-Print KOT for Waiter (only if NOT printing the final bill/settling)
      if (!printBill) {
        if (hasUsbPrinter) {
          final bytes = await ReportService.generateKOTBytes(kotData);
          await ReportService.printBytesIsolated(printerService, bytes);
        } else {
          await ReportService.printKOTReceipt(kotData, orderId);
        }
      }
      
      // If BILL is pressed, print the final bill and settle
      if (printBill) {
        // STEP 1: Settle Firestore and Record Revenue
        // Fetch full order total (previous + new items) for settlement
        final orderDoc = await firestore.collection('orders').doc(orderId).get();
        final finalTotal = (orderDoc.data()?['totalAmount'] as num).toDouble();

        int newReceiptNumber = await ReportService.recordRevenueAndSettle(
          orderId: orderId,
          restaurantId: restaurantId!,
          total: finalTotal,
          paymentMode: paymentMode,
        );

        // STEP 1.5: Clear table if Dine-In
        if (isDineIn && cart.tableId != null) {
          await firestore.collection('tables').doc(cart.tableId).update({
            'status': 'available',
            'currentOrderId': null,
          });
        }

        // Add receipt number for printing
        final printData = Map<String, dynamic>.from(kotData);
        printData['receiptNumber'] = newReceiptNumber;
        printData['paymentMode'] = paymentMode;

        // STEP 2: Generate bytes (pure Dart)
        if (hasUsbPrinter) {
          final bytes = await ReportService.generateFinalBillBytes(
            data: printData,
            total: finalTotal,
            paymentMode: paymentMode,
            hotelName: auth.restaurantName ?? "YUG POS",
          );
          // STEP 3: Print isolated in microtask
          Future.microtask(() async {
            try {
              await ReportService.printBytesIsolated(printerService, bytes);
            } catch (e) {
              debugPrint('Print error: $e');
            }
          });
        } else {
          await ReportService.printFinalBill(
            orderData: printData,
            orderId: orderId,
            subtotal: finalTotal,
            cgst: 0.0,
            sgst: 0.0,
            total: finalTotal,
            paymentMode: paymentMode,
            hotelName: auth.restaurantName ?? "YUG POS",
          );
        }
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

  Future<void> _handleAdminSettle(CartProvider cart, AuthService auth) async {
    // Determine if there is something to settle
    bool hasCartItems = cart.items.isNotEmpty;
    bool hasTableOrder = false;
    String? currentOrderId;
    Map<String, dynamic>? tableOrderData;

    if (cart.orderType == OrderType.dineIn && cart.tableId != null) {
      final tableDoc = await FirebaseFirestore.instance.collection('tables').doc(cart.tableId).get();
      currentOrderId = tableDoc.data()?['currentOrderId'];
      if (currentOrderId != null) {
        hasTableOrder = true;
        final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(currentOrderId).get();
        if (orderDoc.exists) {
          tableOrderData = orderDoc.data() as Map<String, dynamic>;
        }
      }
    }

    if (!hasCartItems && !hasTableOrder) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No items or active order to settle.")));
      return;
    }

    // Step 1: Prompt for payment method
    String selectedPaymentMode = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF141615),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Settle & Clear?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select payment method to finalize revenue.", style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildPaymentOption(
                    title: "CASH", 
                    icon: Icons.money, 
                    isSelected: selectedPaymentMode == 'cash', 
                    onTap: () => setDialogState(() => selectedPaymentMode = 'cash')
                  ),
                  const SizedBox(width: 8),
                  _buildPaymentOption(
                    title: "UPI", 
                    icon: Icons.qr_code, 
                    isSelected: selectedPaymentMode == 'upi', 
                    onTap: () => setDialogState(() => selectedPaymentMode = 'upi')
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFCDD22), foregroundColor: const Color(0xFF141615)),
              child: const Text("SETTLE & CLEAR"),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      if (hasCartItems) {
        // Scenario A: Items in cart - first place KOT then settle
        await _placeOrder(cart, context, printBill: true, paymentMode: selectedPaymentMode);
      } else if (hasTableOrder && currentOrderId != null && tableOrderData != null) {
        // Scenario B: Cart is empty but table has an existing order
        final firestore = FirebaseFirestore.instance;

        final restaurantIdRaw = tableOrderData['restaurantId'] ?? auth.restaurantId;
        final restaurantId = restaurantIdRaw?.toString();
        if (restaurantId == null || restaurantId.isEmpty) {
          throw Exception('Missing restaurantId for settlement');
        }

        // Finalize settlement and record revenue
        int newReceiptNumber = await ReportService.recordRevenueAndSettle(
          orderId: currentOrderId,
          restaurantId: restaurantId,
          total: (tableOrderData['totalAmount'] as num).toDouble(),
          paymentMode: selectedPaymentMode,
        );
        
        final printData = Map<String, dynamic>.from(tableOrderData);
        printData['receiptNumber'] = newReceiptNumber;
        printData['paymentMode'] = selectedPaymentMode;

        // Print bill
        await ReportService.printFinalBill(
          orderData: printData,
          orderId: currentOrderId,
          subtotal: (tableOrderData['totalAmount'] as num).toDouble(),
          cgst: 0, sgst: 0,
          total: (tableOrderData['totalAmount'] as num).toDouble(),
          paymentMode: selectedPaymentMode,
          hotelName: auth.restaurantName ?? "YUG POS",
        );

        // Clear table
        await firestore.collection('tables').doc(cart.tableId).update({
          'status': 'available',
          'currentOrderId': null,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Table Settled! Mode: ${selectedPaymentMode.toUpperCase()}"), backgroundColor: Colors.green));
          cart.clearCart();
          if (widget.isBottomSheet) Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildPaymentOption({required String title, required IconData icon, required bool isSelected, required VoidCallback onTap}) {
    final color = isSelected ? const Color(0xFFFCDD22) : Colors.white10;
    final textColor = isSelected ? const Color(0xFF141615) : Colors.white60;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : Colors.white10),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? textColor : Colors.white38, size: 20),
              const SizedBox(height: 4),
              Text(title, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAdminClearTable(CartProvider cart) async {
    if (cart.orderType == OrderType.dineIn && cart.tableId != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF141615),
          title: const Text("Clear Table?", style: TextStyle(color: Colors.white)),
          content: const Text("This will reset the table status without recording revenue. Continue?", style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text("CLEAR"),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        setState(() => _isSubmitting = true);
        try {
          await FirebaseFirestore.instance.collection('tables').doc(cart.tableId).update({
            'status': 'available',
            'currentOrderId': null,
          });
          cart.clearCart();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Table cleared successfully.")));
            if (widget.isBottomSheet) Navigator.pop(context);
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
      }
    } else {
      cart.clearCart();
    }
  }
}
