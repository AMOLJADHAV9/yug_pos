import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/auth_service.dart';
import '../../../services/urban_piper_service.dart';
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
            labelColor: const Color(0xFFE7FF12),
            unselectedLabelColor: Colors.white54,
            indicatorColor: const Color(0xFFE7FF12),
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
                   const Text("Menu Categories", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                   ElevatedButton.icon(
                     onPressed: () => _showCategoryDialog(restaurantId: restaurantId),
                     icon: const Icon(Icons.add, size: 16, color: Colors.black),
                     label: const Text("New Category", style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold)),
                     style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE7FF12),
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
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: const Color(0xFFE7FF12).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: Center(
                                  child: Text("${data['order'] ?? 0}", style: const TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                                    const SizedBox(height: 2),
                                    Text(visible ? "VISIBLE" : "HIDDEN", style: TextStyle(color: visible ? const Color(0xFFE7FF12) : Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_note, color: const Color(0xFFE7FF12).withOpacity(0.7), size: 20),
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
                   const Text("Menu Items", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    Row(
                      children: [
                        _buildUrbanPiperSyncButton(restaurantId),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showItemDialog(restaurantId: restaurantId),
                          icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.black),
                          label: const Text("Add Item", style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                             backgroundColor: const Color(0xFFE7FF12),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
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
                      const Color accentColor = Color(0xFFE7FF12); // Yellow theme color

                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                                    Text(data['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text(data['category'] ?? 'Gen', style: TextStyle(color: accentColor.withOpacity(0.8), fontSize: 8, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        GestureDetector(onTap: () => _showItemDialog(id: items[index].id, initialData: data, restaurantId: restaurantId), child: Icon(Icons.edit, size: 14, color: const Color(0xFFE7FF12).withOpacity(0.7))),
                                        const SizedBox(width: 12),
                                        GestureDetector(onTap: () => _firestore.collection('menu_items').doc(items[index].id).delete(), child: Icon(Icons.delete, size: 14, color: Colors.redAccent.withOpacity(0.7))),
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
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(id == null ? "Add Category" : "Edit Category", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFE7FF12).withOpacity(0.1))),
        content: Theme(
          data: Theme.of(context).copyWith(
            brightness: Brightness.dark,
            inputDecorationTheme: InputDecorationTheme(
              labelStyle: const TextStyle(color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE7FF12))),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Category Name")),
              TextField(controller: orderCtrl, decoration: const InputDecoration(labelText: "Sort Order"), keyboardType: TextInputType.number),
              SwitchListTile(
                title: const Text("Visible", style: TextStyle(color: Colors.white)), 
                value: isVisible, 
                onChanged: (v) => setDialogState(() => isVisible = v),
                activeColor: const Color(0xFFE7FF12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              final data = {'name': nameCtrl.text.trim(), 'order': int.tryParse(orderCtrl.text) ?? 1, 'isVisible': isVisible, 'restaurantId': restaurantId};
              if (id == null) _firestore.collection('menu_categories').add(data);
              else _firestore.collection('menu_categories').doc(id).update(data);
              Navigator.pop(context);
            }, 
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
            child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ));
  }

  void _showItemDialog({String? id, Map<String, dynamic>? initialData, String? restaurantId}) {
     showDialog(context: context, builder: (_) => ItemEditDialog(id: id, initialData: initialData, restaurantId: restaurantId));
  }

  Widget _buildUrbanPiperSyncButton(String? restaurantId) {
    return IconButton(
      tooltip: "Sync Menu to Zomato/Swiggy (UrbanPiper)",
      icon: const Icon(Icons.cloud_sync, color: Color(0xFFE7FF12)),
      onPressed: () => _showUrbanPiperConfigDialog(restaurantId),
    );
  }

  void _showUrbanPiperConfigDialog(String? restaurantId) {
    final apiCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    bool syncing = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text("UrbanPiper Action", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               const Text("Push your POS menu categories and items to Zomato/Swiggy via UrbanPiper Atlas.", 
                style: TextStyle(color: Colors.white54, fontSize: 13)),
               const SizedBox(height: 16),
               TextField(
                 controller: userCtrl,
                 decoration: const InputDecoration(labelText: "Username / ID", labelStyle: TextStyle(color: Colors.white70)),
                 style: const TextStyle(color: Colors.white),
               ),
               TextField(
                 controller: apiCtrl,
                 decoration: const InputDecoration(labelText: "API Key", labelStyle: TextStyle(color: Colors.white70)),
                 style: const TextStyle(color: Colors.white),
                 obscureText: true,
               ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: syncing ? null : () async {
                setDialogState(() => syncing = true);
                final service = UrbanPiperService();
                final success = await service.syncMenu(restaurantId!, apiCtrl.text.trim(), userCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? "Menu synchronization started!" : "Sync failed. Check credentials."),
                      backgroundColor: success ? Colors.green : Colors.red,
                    )
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
              child: syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("SYNC NOW"),
            ),
          ],
        ),
      ),
    );
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
  bool isAvailable = true;
  bool availableOnline = true;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialData?['name']);
    priceCtrl = TextEditingController(text: widget.initialData?['price']?.toString());
    descCtrl = TextEditingController(text: widget.initialData?['description']);
    selectedCategory = widget.initialData?['category'];
    imageUrl = widget.initialData?['imageUrl'];
    isAvailable = widget.initialData?['isAvailable'] ?? true;
    availableOnline = widget.initialData?['availableOnline'] ?? true;
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
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(widget.id == null ? "Add Menu Item" : "Edit Item", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFE7FF12).withOpacity(0.1))),
      content: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          inputDecorationTheme: InputDecorationTheme(
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE7FF12))),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageUrl != null) 
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imageUrl!, height: 100, width: double.infinity, fit: BoxFit.cover)),
              TextButton.icon(
                onPressed: _pickImage, 
                icon: const Icon(Icons.image, color: Color(0xFFE7FF12)), 
                label: Text(imageUrl == null ? "Upload Image" : "Change Image", style: const TextStyle(color: Color(0xFFE7FF12))),
              ),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Item Name")),
              TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: "Price (INR)"), keyboardType: TextInputType.number),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Description (Optional)")),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('menu_categories').where('restaurantId', isEqualTo: widget.restaurantId).snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox();
                  final cats = snap.data!.docs;
                  return DropdownButtonFormField<String>(
                    dropdownColor: const Color(0xFF2C2C2C),
                    value: cats.any((d) => d['name'] == selectedCategory) ? selectedCategory : null,
                    hint: const Text("Select Category", style: TextStyle(color: Colors.white54)),
                    items: cats.map((d) => DropdownMenuItem(value: d['name'].toString(), child: Text(d['name'], style: const TextStyle(color: Colors.white)))).toList(),
                    onChanged: (v) => setState(() => selectedCategory = v),
                    decoration: const InputDecoration(labelText: "Category"),
                  );
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text("Available in POS", style: TextStyle(fontSize: 14, color: Colors.white)),
                subtitle: const Text("Show/Hide in Table/Takeaway menu", style: TextStyle(fontSize: 11, color: Colors.white54)),
                value: isAvailable, 
                onChanged: (v) => setState(() => isAvailable = v),
                activeColor: const Color(0xFFE7FF12),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text("Available Online (Zomato/Swiggy)", style: TextStyle(fontSize: 14, color: Colors.white)),
                subtitle: const Text("Sync to UrbanPiper Atlas", style: TextStyle(fontSize: 11, color: Colors.white54)),
                value: availableOnline, 
                onChanged: (v) => setState(() => availableOnline = v),
                activeColor: Colors.purpleAccent,
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: loading ? null : () {
            final data = {
              'name': nameCtrl.text.trim(),
              'price': double.tryParse(priceCtrl.text) ?? 0.0,
              'description': descCtrl.text.trim(),
              'category': selectedCategory,
              'imageUrl': imageUrl,
              'isAvailable': isAvailable,
              'availableOnline': availableOnline,
              'restaurantId': widget.restaurantId,
            };
            if (widget.id == null) FirebaseFirestore.instance.collection('menu_items').add(data);
            else FirebaseFirestore.instance.collection('menu_items').doc(widget.id).update(data);
            Navigator.pop(context);
          }, 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
          child: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Text("Save", style: TextStyle(fontWeight: FontWeight.bold))
        ),
      ],
    );
  }
}
