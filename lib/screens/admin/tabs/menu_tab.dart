import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/auth_service.dart';
import 'package:provider/provider.dart';

class MenuTab extends StatefulWidget {
  const MenuTab({super.key});

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  final _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: const [
              Tab(text: "Categories", icon: Icon(Icons.category, size: 20)),
              Tab(text: "Menu Items", icon: Icon(Icons.restaurant, size: 20)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCategoriesView(),
                _buildItemsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesView() {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('menu_categories')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        final cats = (snapshot.data?.docs ?? []).toList();
        // Sort in memory to avoid requiring a composite index
        cats.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text("Menu Categories", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   ElevatedButton.icon(
                     onPressed: () => _showCategoryDialog(restaurantId: restaurantId),
                     icon: const Icon(Icons.add, size: 16),
                     label: const Text("New Category", style: TextStyle(fontSize: 12)),
                     style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                     ),
                   ),
                ],
              ),
            ),
            Expanded(
              child: cats.isEmpty 
                ? const Center(child: Text("No categories yet. Add one to get started!"))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: cats.length,
                    itemBuilder: (context, index) {
                      final data = cats[index].data() as Map<String, dynamic>;
                      final id = cats[index].id;
                      final visible = data['isVisible'] ?? true;
                      const Color accentColor = Colors.deepPurple;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[100]!),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: Center(
                                  child: Text("${data['order'] ?? 0}", style: const TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Text(visible ? "VISIBLE" : "HIDDEN", style: TextStyle(color: visible ? Colors.green : Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_note, color: Colors.blue, size: 20),
                                onPressed: () => _showCategoryDialog(id: id, initialData: data, restaurantId: restaurantId),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => _firestore.collection('menu_categories').doc(id).delete(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItemsView() {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('menu_items')
          .where('restaurantId', isEqualTo: restaurantId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        final items = snapshot.data?.docs ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text("Menu Items", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   ElevatedButton.icon(
                     onPressed: () => _showItemDialog(restaurantId: restaurantId),
                     icon: const Icon(Icons.add_circle_outline, size: 16),
                     label: const Text("Add Item", style: TextStyle(fontSize: 12)),
                     style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                     ),
                   ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  int crossAxis = constraints.maxWidth > 1000 ? 8 : (constraints.maxWidth > 800 ? 7 : (constraints.maxWidth > 600 ? 6 : 5));
                  
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxis,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: isMobile ? 1.0 : 0.7,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final data = items[index].data() as Map<String, dynamic>;
                      final available = data['isAvailable'] ?? true;
                      const Color accentColor = Color(0xFF800000); // Maroon color

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[100]!),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (data['imageUrl'] != null)
                                      Image.network(data['imageUrl'], fit: BoxFit.cover)
                                    else
                                      Container(color: accentColor.withOpacity(0.05), child: Icon(Icons.restaurant, color: accentColor.withOpacity(0.2), size: 24)),
                                    if (!available) Container(color: Colors.black45, child: const Center(child: Text("OFF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)))),
                                    // Top-left Switch overlay
                                    Positioned(
                                      top: 2, left: 2, 
                                      child: Transform.scale(
                                        scale: 0.5, 
                                        child: Switch(
                                          value: available, 
                                          onChanged: (v) => _firestore.collection('menu_items').doc(items[index].id).update({'isAvailable': v}),
                                          activeColor: Colors.green,
                                          inactiveThumbColor: Colors.red,
                                        ),
                                      ),
                                    ),
                                    Positioned(top: 2, right: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)), child: Text("₹${data['price']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Colors.white)))),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text(data['category'] ?? 'Gen', style: const TextStyle(color: accentColor, fontSize: 8, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        GestureDetector(onTap: () => _showItemDialog(id: items[index].id, initialData: data, restaurantId: restaurantId), child: Icon(Icons.edit, size: 14, color: Colors.blue.withOpacity(0.7))),
                                        const SizedBox(width: 12),
                                        GestureDetector(onTap: () => _firestore.collection('menu_items').doc(items[index].id).delete(), child: Icon(Icons.delete, size: 14, color: Colors.red.withOpacity(0.7))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

  void _showCategoryDialog({String? id, Map<String, dynamic>? initialData, String? restaurantId}) {
    final nameCtrl = TextEditingController(text: initialData?['name']);
    final orderCtrl = TextEditingController(text: initialData?['order']?.toString() ?? '1');
    bool isVisible = initialData?['isVisible'] ?? true;

    showDialog(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(id == null ? "Add Category" : "Edit Category"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Category Name")),
            TextField(controller: orderCtrl, decoration: const InputDecoration(labelText: "Sort Order"), keyboardType: TextInputType.number),
            SwitchListTile(title: const Text("Visible"), value: isVisible, onChanged: (v) => setDialogState(() => isVisible = v)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
             final data = {'name': nameCtrl.text.trim(), 'order': int.tryParse(orderCtrl.text) ?? 1, 'isVisible': isVisible, 'restaurantId': restaurantId};
             if (id == null) _firestore.collection('menu_categories').add(data);
             else _firestore.collection('menu_categories').doc(id).update(data);
             Navigator.pop(context);
          }, child: const Text("Save")),
        ],
      ),
    ));
  }

  void _showItemDialog({String? id, Map<String, dynamic>? initialData, String? restaurantId}) {
     showDialog(context: context, builder: (_) => ItemEditDialog(id: id, initialData: initialData, restaurantId: restaurantId));
  }
}

class ItemEditDialog extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? initialData;
  final String? restaurantId;
  const ItemEditDialog({super.key, this.id, this.initialData, this.restaurantId});

  @override
  State<ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<ItemEditDialog> {
  late TextEditingController nameCtrl;
  late TextEditingController priceCtrl;
  late TextEditingController descCtrl;
  String? selectedCategory;
  String? imageUrl;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialData?['name']);
    priceCtrl = TextEditingController(text: widget.initialData?['price']?.toString());
    descCtrl = TextEditingController(text: widget.initialData?['description']);
    selectedCategory = widget.initialData?['category'];
    imageUrl = widget.initialData?['imageUrl'];
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.bytes != null) {
      setState(() => loading = true);
      try {
        final ref = FirebaseStorage.instance.ref('menu/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putData(result.files.single.bytes!);
        final url = await ref.getDownloadURL();
        setState(() => imageUrl = url);
      } finally {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.id == null ? "Add Menu Item" : "Edit Item"),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SingleChildScrollView(
        child: Column(
          children: [
            if (imageUrl != null) Image.network(imageUrl!, height: 100, fit: BoxFit.cover),
            TextButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image), label: Text(imageUrl == null ? "Upload Image" : "Change Image")),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Item Name")),
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: "Price (INR)"), keyboardType: TextInputType.number),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Description (Optional)")),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('menu_categories').where('restaurantId', isEqualTo: widget.restaurantId).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox();
                final cats = snap.data!.docs;
                return DropdownButtonFormField<String>(
                  value: cats.any((d) => d['name'] == selectedCategory) ? selectedCategory : null,
                  hint: const Text("Select Category"),
                  items: cats.map((d) => DropdownMenuItem(value: d['name'].toString(), child: Text(d['name']))).toList(),
                  onChanged: (v) => setState(() => selectedCategory = v),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: loading ? null : () {
            final data = {
              'name': nameCtrl.text.trim(),
              'price': double.tryParse(priceCtrl.text) ?? 0.0,
              'description': descCtrl.text.trim(),
              'category': selectedCategory,
              'imageUrl': imageUrl,
              'isAvailable': widget.initialData?['isAvailable'] ?? true,
              'restaurantId': widget.restaurantId,
            };
            if (widget.id == null) FirebaseFirestore.instance.collection('menu_items').add(data);
            else FirebaseFirestore.instance.collection('menu_items').doc(widget.id).update(data);
            Navigator.pop(context);
          }, 
          child: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Save")
        ),
      ],
    );
  }
}
