import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../models/menu_item.dart';
import '../providers/cart_provider.dart';
import '../services/report_service.dart';
import '../services/usb_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../utils/debouncer.dart';
import '../utils/navigator_utils.dart';
import 'menu_item_card.dart';

class TakeawayOrderDialog extends StatefulWidget {
  final String orderType; // 'takeaway' or 'delivery'
  
  const TakeawayOrderDialog({
    super.key, 
    this.orderType = 'takeaway',
  });

  @override
  State<TakeawayOrderDialog> createState() => _TakeawayOrderDialogState();
}

class _TakeawayOrderDialogState extends State<TakeawayOrderDialog> {
  String _selectedCategory = "All";
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<CartItem> _selectedItems = [];
  final Debouncer _debouncer = Debouncer(milliseconds: 1000);
  bool _isSubmitting = false;

  // Removed _phoneController
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _deliveryBoyController = TextEditingController();
  String _paymentMethod = 'Cash';

  @override
  void dispose() {
    _searchController.dispose();

    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _deliveryBoyController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Dialog(
      backgroundColor: const Color(0xFF141615),
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
      child: Container(
        width: isMobile ? screenWidth : screenWidth * 0.95,
        height: MediaQuery.of(context).size.height * (isMobile ? 1.0 : 0.95),
        color: const Color(0xFF141615),
        child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildDialogHeader(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _buildSearchBar(),
        ),
        _buildCategoryStrip(),
        Expanded(
          child: _buildMenuPane(),
        ),
        if (_selectedItems.isNotEmpty) _buildMobileBottomCart(),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogHeader(),
                const SizedBox(height: 12),
                _buildSearchBar(),
                const SizedBox(height: 12),
                Expanded(child: _buildMenuPane()),
              ],
            ),
          ),
        ),
        _buildCategorySidebar(),
        Container(
          width: 350,
          decoration: BoxDecoration(
            color: const Color(0xFF141615),
            border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: _buildCartPane(),
        ),
      ],
    );
  }

  Widget _buildDialogHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.orderType == 'delivery' ? "New Delivery Order" : "New Takeaway Order", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(widget.orderType == 'delivery' ? "Home Delivery" : "Parcel / Pickup", style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 11)),
                ],
              ),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => safePop(context)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text("Type: ${widget.orderType == 'delivery' ? 'Home Delivery' : 'Pickup / Takeaway'}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
               Row(
                 children: [
                   Expanded(
                     child: TextField(
                       controller: _nameController,
                       style: const TextStyle(color: Colors.white, fontSize: 13),
                       decoration: _inputDecoration("Customer Name"),
                     ),
                   ),
                   const SizedBox(width: 8),
                   Expanded(
                     child: TextField(
                       controller: _phoneController,
                       keyboardType: TextInputType.phone,
                       style: const TextStyle(color: Colors.white, fontSize: 13),
                       decoration: _inputDecoration("Contact Number"),
                     ),
                   ),
                 ],
               ),
               const SizedBox(height: 8),
               TextField(
                 controller: _addressController,
                 style: const TextStyle(color: Colors.white, fontSize: 13),
                 decoration: _inputDecoration(widget.orderType == 'delivery' ? "Delivery Address *" : "Delivery Address (Optional)"),
               ),
               if (widget.orderType == 'delivery') ...[
                 const SizedBox(height: 8),
                 TextField(
                   controller: _deliveryBoyController,
                   style: const TextStyle(color: Colors.white, fontSize: 13),
                   decoration: _inputDecoration("Delivery Boy / Rider (Optional)"),
                 ),
               ],
               const SizedBox(height: 8),
              _buildPaymentMethodSelector(),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true, fillColor: const Color(0xFF141615),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
    );
  }

  Widget _buildPaymentMethodSelector() {
    return Row(
      children: [
        const Text("Payment:", style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(width: 8),
        ...['Cash', 'UPI', 'Card'].map((method) => Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: ChoiceChip(
            label: Text(method, style: TextStyle(fontSize: 10, color: _paymentMethod == method ? const Color(0xFF141615) : Colors.white70)),
            selected: _paymentMethod == method,
            selectedColor: const Color(0xFFFCDD22),
            backgroundColor: Colors.white.withOpacity(0.05),
            onSelected: (val) => setState(() => _paymentMethod = method),
          ),
        )),
      ],
    );
  }

  // Reuse logic from CommonOrderDialog for Menu, Search, etc.
  Widget _buildSearchBar() {
    return Container(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search items...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Color(0xFFFCDD22), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 18, color: Colors.white54), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
            : null,
          filled: true, fillColor: const Color(0xFF141615),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
      ),
    );
  }

  Widget _buildCategoryStrip() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return Container(
      height: 35,
      margin: const EdgeInsets.only(bottom: 4),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('menu_categories')
            .where('restaurantId', isEqualTo: restaurantId)
            .snapshots(),
        builder: (context, snapshot) {
          final List<String> categories = ["All"];
          if (snapshot.hasData) {
            final docs = snapshot.data!.docs.toList();
            docs.sort((a, b) {
               final dataA = a.data() as Map<String, dynamic>;
               final dataB = b.data() as Map<String, dynamic>;
               return (dataA['order'] ?? 0).compareTo(dataB['order'] ?? 0);
            });
            categories.addAll(docs.map((d) => (d.data() as Map<String, dynamic>)['name']?.toString() ?? 'Unknown').toList());
          }

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final name = categories[index];
              final isSelected = _selectedCategory == name;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(name, style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF141615) : Colors.white70
                  )),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  selected: isSelected,
                  selectedColor: const Color(0xFFFCDD22),
                  backgroundColor: Colors.white.withOpacity(0.05),
                  onSelected: (val) {
                    if (val) setState(() => _selectedCategory = name);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMenuPane() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('menu_items')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('isAvailable', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allDocs = snapshot.data!.docs;
        final allItems = allDocs.map((doc) => MenuItem.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();

        final filteredItems = allItems.where((i) {
          final matchesCategory = _selectedCategory == "All" || i.category == _selectedCategory;
          final matchesSearch = _searchQuery.isEmpty || i.name.toLowerCase().contains(_searchQuery);
          return matchesCategory && matchesSearch;
        }).toList();

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 1.0,
          ),
          itemCount: filteredItems.length,
          itemBuilder: (context, index) {
            final item = filteredItems[index];
            final cartIdx = _selectedItems.indexWhere((i) => i.item.id == item.id);
            final count = cartIdx >= 0 ? _selectedItems[cartIdx].quantity : 0;
            final isSelected = count > 0;

                          return MenuItemCard(
                            item: item,
                            isSelected: isSelected,
                            quantity: count,
                            isMobile: true, // Use mobile style for dialog grids
                            onTap: () => setState(() {
                              if (cartIdx >= 0) {
                                _selectedItems[cartIdx].quantity++;
                              } else {
                                _selectedItems.add(CartItem(item: item));
                              }
                            }),
                          );
          },
        );
      },
    );
  }

  Widget _buildCategorySidebar() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('menu_categories')
            .where('restaurantId', isEqualTo: restaurantId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          final cats = (snapshot.data?.docs ?? []).toList();
          cats.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            return (dataA['order'] ?? 0).compareTo(dataB['order'] ?? 0);
          });

          return ListView(
            children: [
              _buildCategoryItem("All", null, _selectedCategory == "All"),
              ...cats.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _buildCategoryItem(
                  data['name']?.toString() ?? 'Unknown', 
                  data['imageUrl']?.toString(), 
                  _selectedCategory == (data['name']?.toString() ?? 'Unknown')
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryItem(String name, String? imageUrl, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedCategory = name),
      child: Container(
        height: 60,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFCDD22) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category, color: isSelected ? const Color(0xFF141615) : Colors.white24, size: 20),
            Text(name, style: TextStyle(fontSize: 9, color: isSelected ? const Color(0xFF141615) : Colors.white70), textAlign: TextAlign.center, maxLines: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildCartPane() {
    final total = _selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity));
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("Order Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
        ),
        Expanded(
          child: _selectedItems.isEmpty
            ? const Center(child: Text("Cart is empty", style: TextStyle(color: Colors.grey)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _selectedItems.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final i = _selectedItems[index];
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.item.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            Text("₹${i.item.price.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20), onPressed: () => setState(() {
                            if (i.quantity > 1) i.quantity--; else _selectedItems.removeAt(index);
                          })),
                          Text("${i.quantity}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFFFCDD22), size: 20), onPressed: () => setState(() => i.quantity++)),
                        ],
                      ),
                    ],
                  );
                },
              ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Color(0xFF141615)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: (_selectedItems.isEmpty || _isSubmitting) ? null : () => _submitOrder(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFCDD22), foregroundColor: const Color(0xFF141615), padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(widget.orderType == 'delivery' ? "PLACE DELIVERY ORDER" : "PLACE TAKEAWAY ORDER", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBottomCart() {
     final total = _selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity));
     return Container(
       padding: const EdgeInsets.all(16),
       color: const Color(0xFFFCDD22),
       child: SafeArea(top: false, child: Row(
         mainAxisAlignment: MainAxisAlignment.spaceBetween,
         children: [
           Text("Total: ₹${total.toStringAsFixed(0)}", style: const TextStyle(color: const Color(0xFF141615), fontWeight: FontWeight.bold, fontSize: 18)),
           ElevatedButton(
             onPressed: _isSubmitting ? null : () => _submitOrder(),
             style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF141615), foregroundColor: Colors.white),
             child: const Text("PLACE ORDER"),
           ),
         ],
       )),
     );
  }

  void _submitOrder() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final auth = context.read<AuthService>();
      final restaurantId = auth.restaurantId;
      final waiterName = auth.role == UserRole.admin ? "Admin" : (auth.role == UserRole.cashier ? "Cashier" : "Waiter");
      
      final address = _addressController.text.trim();
      final deliveryBoy = _deliveryBoyController.text.trim();
      final cName = _nameController.text.trim();
      final cPhone = _phoneController.text.trim();

      // Validation for Delivery (Address only now)
      if (widget.orderType == 'delivery' && address.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Delivery address is required."), backgroundColor: Colors.red));
        }
        return;
      }

      final customerName = cName.isNotEmpty ? cName : (widget.orderType == 'delivery' ? "Delivery Customer" : "Takeaway");
      final total = _selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity));

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final orderRef = firestore.collection('orders').doc();

      batch.set(orderRef, {
        'orderType': widget.orderType,
        'tableName': widget.orderType == 'delivery' ? 'Delivery' : 'Takeaway',
        'tableId': widget.orderType,
        'customerName': customerName,
        'customerPhone': cPhone.isNotEmpty ? cPhone : null,
        'deliveryAddress': address,
        'deliveryBoy': deliveryBoy.isEmpty ? null : deliveryBoy,
        'deliveryStatus': widget.orderType == 'delivery' ? 'pending' : null,
        'takeawayStatus': widget.orderType == 'takeaway' ? 'pending' : null,
        'paymentMethod': _paymentMethod,
        'status': 'open',
        'isDelivered': false,
        'restaurantId': restaurantId,
        'waiterName': waiterName,
        'createdAt': FieldValue.serverTimestamp(),
        'totalAmount': total,
        'items': _selectedItems.map((i) => {
          'id': i.item.id,
          'name': i.item.name,
          'price': i.item.price,
          'quantity': i.quantity,
        }).toList(),
      });

      final itemsRef = orderRef.collection('items');
      for (var i in _selectedItems) {
        batch.set(itemsRef.doc(), {
          'menuItemId': i.item.id,
          'name': i.item.name,
          'price': i.item.price,
          'quantity': i.quantity,
          'totalPrice': i.item.price * i.quantity,
          'status': 'Pending',
          'restaurantId': restaurantId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final kotRef = firestore.collection('kots').doc();
      batch.set(kotRef, {
        'orderId': orderRef.id,
        'tableName': widget.orderType == 'delivery' ? 'Delivery' : 'Takeaway',
        'tableId': widget.orderType,
        'customerName': customerName,
        'status': 'Pending',
        'restaurantId': restaurantId,
        'createdAt': FieldValue.serverTimestamp(),
        'waiterName': waiterName,
        'items': _selectedItems.map((i) => {'name': i.item.name, 'quantity': i.quantity}).toList(),
      });

      await batch.commit();
      
      final kotData = {
        'tableName': widget.orderType == 'delivery' ? 'Delivery' : 'Takeaway',
        'customerName': customerName,
        'waiterName': waiterName,
        'restaurantId': restaurantId, 
        'totalAmount': total,
        'items': _selectedItems.map((i) => {'name': i.item.name, 'quantity': i.quantity, 'price': i.item.price}).toList(),
      };

      final usb = context.read<UsbPrinterService>();
      final bt = context.read<BluetoothPrinterService>();
      final isAndroid = !kIsWeb && Platform.isAndroid;
      final dynamic printerService = isAndroid ? bt : usb;
      final paymentMode = _paymentMethod;
      final hotelName = context.read<AuthService>().restaurantName ?? "YUG POS";

      // STEP 1: Settle Firestore (main thread)
      final receiptNo = await ReportService.recordRevenueAndSettle(
        orderId: orderRef.id,
        restaurantId: restaurantId!,
        total: total,
        paymentMode: paymentMode,
      );

      // STEP 2: Smart Print (Thermal if configured, else PDF fallback)
      await ReportService.printFinalBill(
        orderData: kotData,
        orderId: orderRef.id,
        subtotal: total,
        total: total,
        paymentMode: paymentMode,
        hotelName: hotelName,
        receiptNum: receiptNo.toString(),
        printerService: printerService,
      );

      if (mounted) {
        safePop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.orderType == 'delivery' ? "Delivery Order Placed!" : "Takeaway Order Placed!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

}
