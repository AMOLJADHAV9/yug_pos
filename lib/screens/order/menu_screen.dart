import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../models/table_model.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/cart_bottom_sheet.dart';
import '../../widgets/cart_view_content.dart';
import '../../utils/navigator_utils.dart';

class MenuScreen extends StatefulWidget {
  final TableModel table;
  const MenuScreen({
    super.key, 
    required this.table, 
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cart = context.read<CartProvider>();
      cart.setTable(widget.table.id, widget.table.name);
      cart.setCustomerName("Walk-in");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141615),
        elevation: 0,
        title: Text('Table ${widget.table.name} Menu', style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Color(0xFFFCDD22)),
      ),
      body: Column(
        children: [
          _buildCategoryTabs(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    children: [
                      Expanded(flex: 3, child: _buildMenuGrid()),
                      VerticalDivider(width: 1, color: Colors.grey[200]),
                      const Expanded(flex: 1, child: CartViewContent()),
                    ],
                  );
                }
                return _buildMenuGrid();
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (MediaQuery.of(context).size.width > 900) return const SizedBox.shrink();
          return Consumer<CartProvider>(
            builder: (context, cart, child) {
              if (cart.items.isEmpty) return const SizedBox.shrink();
              return InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const CartBottomSheet(),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFFFCDD22),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFF141615).withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                          child: Text('${cart.totalItems}', style: const TextStyle(color: const Color(0xFF141615), fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        const Row(
                          children: [
                            Text('View Cart', style: TextStyle(color: const Color(0xFF141615), fontWeight: FontWeight.bold, fontSize: 16)),
                            SizedBox(width: 8),
                            Icon(Icons.shopping_cart_outlined, color: const Color(0xFF141615))
                          ],
                        ),
                        Text('₹${cart.totalAmount.toStringAsFixed(0)}', style: const TextStyle(color: const Color(0xFF141615), fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return FutureBuilder<QuerySnapshot>(
      future: _firestore.collection('menu_categories')
          .where('restaurantId', isEqualTo: restaurantId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 8)));
        
        final List<String> categories = ['All'];
        if (snapshot.hasData) {
           final docs = snapshot.data!.docs.toList();
           // Optional in-memory sort to avoid index requirement
           docs.sort((a, b) => (a.get('order') ?? 0).compareTo(b.get('order') ?? 0));
           categories.addAll(docs.map((d) => d.get('name').toString()));
        }

        return SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 10, bottom: 10),
                child: ChoiceChip(
                  label: Text(cat, style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF141615) : Colors.white70
                  )),
                  selected: isSelected,
                  selectedColor: const Color(0xFFFCDD22),
                  backgroundColor: const Color(0xFF141615),
                  onSelected: (val) {
                    if (val) setState(() => _selectedCategory = cat);
                  },
                ),
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildMenuGrid() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return FutureBuilder<QuerySnapshot>(
      future: _firestore.collection('menu_items')
          .where('restaurantId', isEqualTo: restaurantId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final items = snapshot.data!.docs.map((d) => MenuItem.fromMap(d.id, d.data() as Map<String,dynamic>))
            .where((item) => _selectedCategory == 'All' || item.category == _selectedCategory).toList();
            
        return LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount = 5; // Increased from 2 to 5 for ultra-compact mobile
            if (constraints.maxWidth > 1200) {
              crossAxisCount = 8;
            } else if (constraints.maxWidth > 900) {
              crossAxisCount = 6;
            } else if (constraints.maxWidth > 600) {
              crossAxisCount = 5;
            }

            return GridView.builder(
              padding: const EdgeInsets.all(8), // Reduced padding
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.72, // Taller to fit vertical stack
                crossAxisSpacing: 6, // Reduced spacing
                mainAxisSpacing: 6,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Consumer<CartProvider>(
                  builder: (context, cart, child) {
                    final cartIdx = cart.items.indexWhere((i) => i.item.id == item.id);
                    final quantity = cartIdx >= 0 ? cart.items[cartIdx].quantity : 0;
                    return _buildMenuItemCard(item, quantity);
                  },
                );
              },
            );
          },
        );
      }
    );
  }

  Widget _buildMenuItemCard(MenuItem item, int quantity) {
    final bool isSelected = quantity > 0;
    return Stack(
      children: [
        Card(
          elevation: isSelected ? 4 : 1,
          clipBehavior: Clip.antiAlias,
          color: const Color(0xFF141615),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected ? const BorderSide(color: Color(0xFFFCDD22), width: 1.5) : BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
          child: InkWell(
            onTap: item.isAvailable ? () {
              context.read<CartProvider>().addItem(item);
            } : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    color: const Color(0xFF141615).withOpacity(0.2),
                    child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                        ? Image.network(item.imageUrl!, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.fastfood, size: 28, color: Colors.white24))
                        : const Icon(Icons.fastfood, size: 28, color: Colors.white24),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('₹${item.price.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold, fontSize: 9)),
                          if (!item.isAvailable)
                            const Text('Out', style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold)),
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
        if (isSelected)
          Positioned(
            top: 4, right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFFCDD22), borderRadius: BorderRadius.circular(8)),
              child: Text("$quantity", style: const TextStyle(color: const Color(0xFF141615), fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  void _showQuantitySelector(MenuItem item) {
    int quantity = 1;
    String instructions = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141615),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFFCDD22).withOpacity(0.1))),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 32, color: Color(0xFFFCDD22)),
                        onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
                      ),
                      const SizedBox(width: 16),
                      Text('$quantity', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 32, color: Color(0xFFFCDD22)),
                        onPressed: () => setState(() => quantity++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Theme(
                    data: ThemeData.dark().copyWith(
                      inputDecorationTheme: InputDecorationTheme(
                        labelStyle: const TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFCDD22))),
                      ),
                    ),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Special Instructions',
                        hintText: 'e.g. No onion',
                        hintStyle: TextStyle(color: Colors.white24),
                      ),
                      onChanged: (val) => instructions = val,
                    ),
                  )
                ],
              ),
              actions: [
                TextButton(onPressed: () => safePop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                ElevatedButton(
                  onPressed: () {
                    context.read<CartProvider>().addItem(item, quantity: quantity, instructions: instructions);
                    safePop(context);
                  }, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFCDD22),
                    foregroundColor: const Color(0xFF141615),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: const Text('Add to Cart', style: TextStyle(fontWeight: FontWeight.bold))
                ),
              ],
            );
          }
        );
      }
    );
  }
}
