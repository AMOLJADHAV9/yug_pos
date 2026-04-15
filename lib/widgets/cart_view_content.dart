import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../services/usb_printer_service.dart';
import '../../services/bluetooth_printer_service.dart';
import '../providers/cart_provider.dart';
import '../utils/navigator_utils.dart';

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
                        safePop(context);
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

  Future<void> _placeOrder(CartProvider cart, BuildContext context, {bool printBill = false, String paymentMode = "Cash", bool skipGuard = false}) async {
    if (!skipGuard && _isSubmitting) return;
    
    final isDineIn = cart.orderType == OrderType.dineIn;
    if (isDineIn && cart.tableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a table for Dine-In orders")));
      return;
    }
    
    setState(() => _isSubmitting = true);
    final firestore = FirebaseFirestore.instance;

    try {
      final auth = context.read<AuthService>();
      final restaurantId = auth.restaurantId;
      if (restaurantId == null) throw Exception("Restaurant ID not found");

      // Fetch GST settings
      final settingsDoc = await firestore.collection('settings').doc(restaurantId).get();
      final settings = settingsDoc.data();
      final double _gstPercentage = (settings?['gstPercentage'] ?? 5.0).toDouble();

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

      final String orderId = cart.activeOrderId ?? (isDineIn && tableData?['currentOrderId'] != null 
          ? tableData!['currentOrderId'] 
          : firestore.collection('orders').doc().id);
      
      final orderRef = firestore.collection('orders').doc(orderId);
      final bool isNewOrder = cart.activeOrderId == null && (tableData?['currentOrderId'] == null || !isDineIn);

      final subtotal = cart.totalAmount;
      final total = subtotal * (1 + (_gstPercentage / 100));
      final int totalItemsCount = cart.totalItems;
      final int kotTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      int kotNo = 1;
      final batch = firestore.batch();

      if (isNewOrder) {
        batch.set(orderRef, {
          'tableId': isDineIn ? cart.tableId : null,
          'tableName': tableName ?? 'Unknown',
          'orderType': cart.orderType.name,
          'waiterName': cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter',
          'customerName': cart.customerName ?? 'Walk-in',
          'status': 'active',
          'takeawayStatus': cart.orderType == OrderType.takeaway ? 'pending' : null,
          'deliveryStatus': cart.orderType == OrderType.delivery ? 'pending' : null,
          'isDelivered': false,
          'restaurantId': restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
          'totalAmount': total,
          'subtotal': subtotal,
          'totalItems': totalItemsCount,
          'gstPercentage': _gstPercentage,
          'kotCount': 1,
          'items': cart.items.map((i) => {
            'id': i.item.id,
            'name': i.item.name,
            'price': i.item.price,
            'quantity': i.quantity,
            'category': i.item.category,
            'kotNo': 1,
            'kotTimestamp': kotTimestamp,
            'specialInstructions': i.specialInstructions,
          }).toList(),
        });
        
        if (isDineIn && cart.tableId != null) {
          batch.update(firestore.collection('tables').doc(cart.tableId), {
            'status': 'occupied',
            'currentOrderId': orderId,
          });
        }
      } else {
        // Fetch current order to get kotCount
        final orderDoc = await orderRef.get();
        if (orderDoc.exists) {
          kotNo = (orderDoc.data()?['kotCount'] ?? 1) + 1;
        }

        batch.update(orderRef, {
          'items': FieldValue.arrayUnion(cart.items.map((i) => {
            'id': i.item.id,
            'name': i.item.name,
            'price': i.item.price,
            'quantity': i.quantity,
            'category': i.item.category,
            'kotNo': kotNo,
            'kotTimestamp': kotTimestamp,
            'specialInstructions': i.specialInstructions,
          }).toList()),
          'totalAmount': FieldValue.increment(total),
          'subtotal': FieldValue.increment(subtotal),
          'totalItems': FieldValue.increment(totalItemsCount),
          'gstPercentage': _gstPercentage,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'kotCount': kotNo,
        });
      }

      // Create KOT record
      final kotRef = firestore.collection('kots').doc();
      final kotId = kotRef.id;
      final kNoStr = "KOT #$kotNo";

      batch.set(kotRef, {
        'orderId': orderId,
        'tableId': isDineIn ? cart.tableId : null,
        'tableName': tableName ?? 'Unknown',
        'orderType': cart.orderType.name,
        'customerName': cart.customerName ?? 'Walk-in',
        'waiterName': cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter',
        'status': 'Pending',
        'restaurantId': restaurantId,
        'kotNo': kotNo,
        'kotId': kotId,
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'specialInstructions': i.specialInstructions,
        }).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      
      // Prepare data for printing
      final kotData = {
        'tableName': tableName ?? 'Unknown',
        'customerName': cart.customerName ?? 'Walk-in',
        'waiterName': cart.waiterName ?? (auth.role == UserRole.waiter ? auth.userName : 'Waiter') ?? 'Waiter',
        'cashierName': auth.userName ?? 'Staff',
        'kotNo': kotNo,
        'restaurantId': restaurantId,
        'orderType': cart.orderType.name,
        'createdAt': Timestamp.now(),
        'items': cart.items.map((i) => {
          'name': i.item.name,
          'quantity': i.quantity,
          'price': i.item.price,
        }).toList(),
      };

      final usb = context.read<UsbPrinterService>();
      final bt = context.read<BluetoothPrinterService>();
      final isAndroid = !kIsWeb && Platform.isAndroid;

      if (!printBill) {
        await ReportService.printKOTReceipt(
          kotData, 
          orderId, 
          printerService: isAndroid ? bt : usb,
        );
      }
      
      if (printBill) {
        final orderDoc = await orderRef.get();
        final finalTotal = (orderDoc.data()?['totalAmount'] as num).toDouble();

        int newReceiptNumber = await ReportService.recordRevenueAndSettle(
          orderId: orderId,
          restaurantId: restaurantId,
          total: finalTotal,
          paymentMode: paymentMode,
        );

        if (isDineIn && cart.tableId != null) {
          await firestore.collection('tables').doc(cart.tableId).update({
            'status': 'available',
            'currentOrderId': null,
          });
        }

        final printData = Map<String, dynamic>.from(orderDoc.data()!);
        printData['receiptNumber'] = newReceiptNumber;
        printData['paymentMode'] = paymentMode;

        await ReportService.printFinalBill(
          orderData: printData,
          orderId: orderId,
          subtotal: (orderDoc.data()?['subtotal'] as num?)?.toDouble() ?? finalTotal,
          total: finalTotal,
          paymentMode: paymentMode,
          hotelName: auth.restaurantName ?? "YUG POS",
          receiptNum: newReceiptNumber.toString(),
          printerService: isAndroid ? bt : usb,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order Placed! $kNoStr'),
          backgroundColor: Colors.green,
        ));
        cart.clearCart();
        if (widget.isBottomSheet) {
           safePop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to place order: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleAdminSettle(CartProvider cart, AuthService auth) async {
    if (_isSubmitting) return;

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
            TextButton(onPressed: () => safePop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () => safePop(c, true),
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
        await _placeOrder(cart, context, printBill: true, paymentMode: selectedPaymentMode, skipGuard: true);
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
        printData['restaurantId'] = restaurantId; // Added for receipt metadata
        printData['receiptNumber'] = newReceiptNumber;
        printData['paymentMode'] = selectedPaymentMode;

        final usb = context.read<UsbPrinterService>();
        final bt = context.read<BluetoothPrinterService>();
        final isAndroid = !kIsWeb && Platform.isAndroid;
        final dynamic printerService = isAndroid ? bt : usb;

        // Smart Print (Thermal if configured, else PDF fallback)
        await ReportService.printFinalBill(
          orderData: printData,
          orderId: currentOrderId,
          subtotal: (tableOrderData['totalAmount'] as num).toDouble(),
          total: (tableOrderData['totalAmount'] as num).toDouble(),
          paymentMode: selectedPaymentMode,
          hotelName: auth.restaurantName ?? "YUG POS",
          receiptNum: newReceiptNumber.toString(),
          printerService: isAndroid ? bt : usb,
        );

        // Clear table
        await firestore.collection('tables').doc(cart.tableId).update({
          'status': 'available',
          'currentOrderId': null,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Table Settled! Mode: ${selectedPaymentMode.toUpperCase()}"), backgroundColor: Colors.green));
          cart.clearCart();
          if (widget.isBottomSheet) safePop(context);
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
            TextButton(onPressed: () => safePop(context), child: const Text("Cancel")),
            TextButton(
              onPressed: () => safePop(ctx, true),
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
            if (widget.isBottomSheet) safePop(context);
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
