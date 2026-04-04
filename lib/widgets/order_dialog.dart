import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../utils/navigator_utils.dart';
import '../models/table_model.dart';
import '../models/menu_item.dart';
import '../providers/cart_provider.dart';
import '../services/report_service.dart';
import '../services/usb_printer_service.dart';
import '../utils/debouncer.dart';

class CommonOrderDialog extends StatefulWidget {
  final TableModel table;
  const CommonOrderDialog({super.key, required this.table});

  @override
  State<CommonOrderDialog> createState() => _CommonOrderDialogState();
}

class _CommonOrderDialogState extends State<CommonOrderDialog> {
  String _selectedCategory = "All";
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<CartItem> _selectedItems = [];
  final Debouncer _debouncer = Debouncer(milliseconds: 1000);

  @override
  void dispose() {
    _searchController.dispose();
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

  Widget _buildCategoryStrip() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return Container(
      height: 35,
      margin: const EdgeInsets.only(bottom: 4),
      child: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('menu_categories')
            .where('restaurantId', isEqualTo: restaurantId)
            .get(),
        builder: (context, snapshot) {
          final List<String> categories = ["All"];
          if (snapshot.hasData) {
            final docs = snapshot.data!.docs.toList();
            docs.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));
            categories.addAll(docs.map((d) => d['name'] as String).toList());
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

  Widget _buildMobileBottomCart() {
    final total = _selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity));
    final count = _selectedItems.fold(0, (sum, i) => sum + i.quantity);

    return InkWell(
      onTap: _showCartDetailsBottomSheet,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFCDD22),
          boxShadow: [BoxShadow(color: const Color(0xFF141615).withOpacity(0.2), blurRadius: 10, offset: const Offset(0, -5))],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text("$count ITEMS", style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
                   Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(color: const Color(0xFF141615), fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const Row(
                children: [
                  Text("VIEW CART", style: TextStyle(color: Color(0xFF141615), fontWeight: FontWeight.bold)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_right, color: Color(0xFF141615)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCartDetailsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Color(0xFF141615),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(
                   child: _buildCartPaneWithCallback((updatedItems) {
                      setState(() {});
                      setSheetState(() {});
                   }),
                ),
              ],
            ),
          );
        }
      ),
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
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF141615),
            border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: _buildCartPane(),
        ),
      ],
    );
  }

  Widget _buildCategorySidebar() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return Container(
      width: 110,
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            width: double.infinity,
            color: Colors.white.withOpacity(0.05),
            child: const Center(child: Text("Categories", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white54))),
          ),
          Expanded(
            child: FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('menu_categories')
                  .where('restaurantId', isEqualTo: restaurantId)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final cats = (snapshot.data?.docs ?? []).toList();
                cats.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));

                return ListView(
                  children: [
                    _buildCategoryItem("All", null, _selectedCategory == "All"),
                    ...cats.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name'] ?? 'N/A';
                      final imageUrl = data['imageUrl'];
                      return _buildCategoryItem(name, imageUrl, _selectedCategory == name);
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(String name, String? imageUrl, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedCategory = name),
      child: Container(
        height: 70,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFCDD22) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFFFCDD22) : Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1.8,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                child: imageUrl != null 
                  ? Image.network(imageUrl, fit: BoxFit.cover)
                  : Icon(Icons.category, color: isSelected ? const Color(0xFF141615) : Colors.white24, size: 20),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    name, 
                    style: TextStyle(
                      fontSize: 9, 
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFF141615) : Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Table ${widget.table.name}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(DateFormat('dd MMM, hh:mm a').format(DateTime.now()), style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            Row(
              children: [
                 Text("Total: ₹${_selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity)).toStringAsFixed(0)}", 
                   style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFCDD22))),
                 const SizedBox(width: 16),
                 IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ],
        ),
        const Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text("Customer: Walk-in", style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
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
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFFCDD22))),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
      ),
    );
  }

  Widget _buildMenuPane() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('menu_items')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('isAvailable', isEqualTo: true)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allDocs = snapshot.data!.docs;
        final allItems = allDocs.map((doc) => MenuItem.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();

        final filteredItems = allItems.where((i) {
          final matchesCategory = _selectedCategory == "All" || i.category == _selectedCategory;
          final matchesSearch = _searchQuery.isEmpty || i.name.toLowerCase().contains(_searchQuery);
          return matchesCategory && matchesSearch;
        }).toList();

        return Column(
          children: [
            Expanded(
              child: filteredItems.isEmpty
                ? const Center(child: Text("No items available.", style: TextStyle(color: Colors.grey)))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth < 360 ? 5 : (constraints.maxWidth < 600 ? 6 : 7);
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final cartIdx = _selectedItems.indexWhere((i) => i.item.id == item.id);
                          final count = cartIdx >= 0 ? _selectedItems[cartIdx].quantity : 0;
                          final isSelected = count > 0;

                          return InkWell(
                            onTap: () => setState(() {
                              if (cartIdx >= 0) {
                                _selectedItems[cartIdx].quantity++;
                              } else {
                                _selectedItems.add(CartItem(item: item));
                              }
                            }),
                            child: Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFFCDD22).withOpacity(0.08) : const Color(0xFF141615),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isSelected ? const Color(0xFFFCDD22) : Colors.white.withOpacity(0.05)),
                                    ),
                                    child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF141615).withOpacity(0.4),
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: item.imageUrl != null 
                                              ? Image.network(item.imageUrl!, fit: BoxFit.cover, width: double.infinity)
                                              : const Center(child: Icon(Icons.fastfood, size: 20, color: Colors.white10)),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 2),
                                            Text("₹${item.price.toStringAsFixed(0)}", style: TextStyle(color: isSelected ? const Color(0xFFFCDD22) : Colors.white38, fontWeight: FontWeight.bold, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 2, right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFFCDD22), borderRadius: BorderRadius.circular(8)),
                                      child: Text("$count", style: const TextStyle(color: Color(0xFF141615), fontSize: 8, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCartPane() {
    return _buildCartPaneWithCallback(null);
  }

  Widget _buildCartPaneWithCallback(Function(List<CartItem>)? onChange) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("Cart Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
        ),
        Divider(height: 1, color: Colors.white.withOpacity(0.05)),

        Expanded(
          child: _selectedItems.isEmpty
            ? const Center(child: Text("Cart is empty", style: TextStyle(color: Colors.grey)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _selectedItems.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final i = _selectedItems[index];
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.item.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                            Text("₹${i.item.price.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 22),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () => setState(() {
                              if (_selectedItems[index].quantity > 1) {
                                _selectedItems[index].quantity--;
                              } else {
                                _selectedItems.removeAt(index);
                                if (_selectedItems.isEmpty) {
                                  // Don't pop on desktop, only on mobile if you want
                                }
                              }
                              if (onChange != null) onChange(_selectedItems);
                            }),
                          ),
                          Text("${i.quantity}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Color(0xFFFCDD22), size: 22),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () => setState(() {
                               _selectedItems[index].quantity++;
                               if (onChange != null) onChange(_selectedItems);
                            }),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
        ),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141615),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(
                    "₹${_selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity)).toStringAsFixed(0)}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFCDD22)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _selectedItems.isEmpty ? null : () => _debouncer.run(() => _submitOrder()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFCDD22),
                  foregroundColor: const Color(0xFF141615),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("PLACE ORDER (SEND KOT)", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _submitOrder() async {
    final auth = context.read<AuthService>();
    final waiterDisplayName = auth.role == UserRole.admin 
        ? "Admin (${auth.currentUser?.email?.split('@')[0] ?? 'Admin'})" 
        : "Cashier";
    final total = _selectedItems.fold<double>(0, (sum, i) => sum + (i.item.price * i.quantity));
    const customerName = "Walk-in";

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final orderRef = firestore.collection('orders').doc();
    
    batch.set(orderRef, {
      'tableId': widget.table.id,
      'tableName': widget.table.name,
      'waiterName': waiterDisplayName,
      'customerName': customerName,
      'status': 'open',
      'restaurantId': auth.restaurantId,
      'createdAt': FieldValue.serverTimestamp(),
      'totalAmount': total,
      'items': _selectedItems.map((i) => {
        'id': i.item.id,
        'name': i.item.name,
        'price': i.item.price,
        'quantity': i.quantity,
        'category': i.item.category,
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
        'category': i.item.category,
        'restaurantId': auth.restaurantId,
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final kotRef = firestore.collection('kots').doc();
    batch.set(kotRef, {
      'orderId': orderRef.id,
      'tableId': widget.table.id,
      'tableName': widget.table.name,
      'customerName': customerName,
      'status': 'Pending',
      'restaurantId': auth.restaurantId,
      'createdAt': FieldValue.serverTimestamp(),
      'waiterName': waiterDisplayName,
      'items': _selectedItems.map((i) => {
        'name': i.item.name,
        'quantity': i.quantity,
      }).toList(),
    });

    final tableRef = firestore.collection('tables').doc(widget.table.id);
    batch.update(tableRef, {
      'status': TableStatus.occupied.name,
      'currentOrderId': orderRef.id,
    });

    await batch.commit();

    final kotData = {
      'tableName': widget.table.name,
      'customerName': customerName,
      'waiterName': waiterDisplayName,
      'items': _selectedItems.map((i) => {
        'name': i.item.name,
        'quantity': i.quantity,
        'price': i.item.price,
      }).toList(),
    };
    
    final printerService = context.read<UsbPrinterService>();
    if (printerService.hasSavedPrinter) {
      final bytes = await ReportService.generateKOTBytes(kotData);
      await ReportService.printBytesIsolated(printerService, bytes);
    } else {
      await ReportService.printKOTReceipt(kotData, orderRef.id);
    }

    if (mounted) {
      safePop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Order placed successfully!"), 
        backgroundColor: Colors.green
      ));
    }
  }
}
