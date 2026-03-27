import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../models/table_model.dart';
import '../../../services/report_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/order_dialog.dart';

class TablesTab extends StatefulWidget {
  const TablesTab({super.key});

  @override
  State<TablesTab> createState() => _TablesTabState();
}

class _TablesTabState extends State<TablesTab> {
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
              Tab(text: "Sections", icon: Icon(Icons.layers, size: 20)),
              Tab(text: "Tables", icon: Icon(Icons.table_bar, size: 20)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSectionsView(),
                _buildTablesView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionsView() {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('sections').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final sections = snapshot.data!.docs;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text("Room Sections", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                   ElevatedButton.icon(
                     onPressed: () => _showSectionDialog(restaurantId: restaurantId),
                     icon: const Icon(Icons.add, size: 16, color: Colors.black),
                     label: const Text("New Section", style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold)),
                     style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE7FF12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                     ),
                   ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sections.length,
                itemBuilder: (context, index) {
                  final data = sections[index].data() as Map<String, dynamic>;
                  final id = sections[index].id;
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.white.withOpacity(0.05))),
                    child: ListTile(
                      dense: true,
                      title: Text(data['name'] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _deleteSection(id),
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

  Widget _buildTablesView() {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final tables = snapshot.data!.docs;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text("Table Layout", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                   ElevatedButton.icon(
                     onPressed: () => _showTableDialog(restaurantId: restaurantId),
                     icon: const Icon(Icons.add, size: 16, color: Colors.black),
                     label: const Text("Create Table", style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold)),
                     style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE7FF12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                     ),
                   ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridWidth = constraints.maxWidth;
                  final isMobile = gridWidth < 600;
                  // REQ: 4 cards on mobile
                  final crossAxis = isMobile ? 4 : (gridWidth < 900 ? 5 : 8);
                  
                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxis, 
                      crossAxisSpacing: 6, 
                      mainAxisSpacing: 6,
                      childAspectRatio: isMobile ? 0.65 : 1.0, 
                    ),
                    itemCount: tables.length,
                    itemBuilder: (context, index) {
                      final table = TableModel.fromMap(tables[index].id, tables[index].data() as Map<String, dynamic>);
                      final isOccupied = table.status == TableStatus.occupied || table.status == TableStatus.kotSent || table.status == TableStatus.billRequested;
                      
                      return Container(
                        decoration: BoxDecoration(
                          color: isOccupied ? const Color(0xFFE7FF12).withOpacity(0.05) : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isOccupied ? const Color(0xFFE7FF12).withOpacity(0.5) : const Color(0xFFE7FF12).withOpacity(0.1), width: 0.8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text(table.name, style: TextStyle(fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis)),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(icon: const Icon(Icons.edit, size: 10, color: Color(0xFFE7FF12)), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _showTableDialog(table: table, restaurantId: restaurantId)),
                                      const SizedBox(width: 2),
                                      IconButton(icon: const Icon(Icons.delete, size: 10, color: Colors.redAccent), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () {
                                         _firestore.collection('tables').doc(table.id).delete();
                                      }),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              _buildUltraMiniStatus(table.status),
                              const SizedBox(height: 4),
                              if (!isMobile) ...[
                                Text("Sec: ${table.section}", style: const TextStyle(color: Colors.white60, fontSize: 8), overflow: TextOverflow.ellipsis),
                                Text("Cap: ${table.capacity}", style: const TextStyle(color: Colors.white60, fontSize: 8)),
                                const Spacer(),
                              ] else ...[
                                const Spacer(),
                                Text("C:${table.capacity}", style: const TextStyle(color: Colors.white60, fontSize: 8), textAlign: TextAlign.right),
                              ],
                              
                              const SizedBox(height: 2),
                              if (isOccupied && table.status != TableStatus.billRequested)
                                _buildUltraCompactButton("BILL", Icons.receipt_long, Colors.red, () => _requestBill(table)),
                              
                              _buildUltraCompactButton("ORDER", Icons.add_shopping_cart, Colors.green, () {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => CommonOrderDialog(table: table),
                                );
                              }),

                              if (isOccupied)
                                _buildUltraCompactButton("CLR", Icons.cleaning_services, Colors.blue, () => _showClearTableDialog(table)),
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

  Widget _buildUltraCompactButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: SizedBox(
        width: double.infinity,
        height: 22,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 8),
          label: Text(label, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
    );
  }

  Widget _buildUltraMiniStatus(TableStatus status) {
    Color color = Colors.green;
    String text = "LIV";
    IconData icon = Icons.check_circle_outline;

    if (status == TableStatus.occupied) {
      color = Colors.orange;
      text = "OCC";
      icon = Icons.people;
    } else if (status == TableStatus.kotSent) {
      color = Colors.blue;
      text = "KOT";
      icon = Icons.restaurant;
    } else if (status == TableStatus.billRequested) {
      color = Colors.red;
      text = "BILL";
      icon = Icons.receipt_long;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.5), width: 0.5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 8),
          const SizedBox(width: 2),
          Text(text, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _requestBill(TableModel table) async {
    await _firestore.collection('tables').doc(table.id).update({'status': 'billRequested'});
  }

  void _showClearTableDialog(TableModel table) {
    if (table.currentOrderId == null) {
      _processClearTable(table);
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text("Clear Table ${table.name}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Would you like to print the final bill before clearing this table?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          OutlinedButton(onPressed: () { Navigator.pop(context); _processClearTable(table, printBill: false); }, style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white24), foregroundColor: Colors.white), child: const Text("Clear Only")),
          ElevatedButton.icon(
            onPressed: () { Navigator.pop(context); _processClearTable(table, printBill: true); },
            icon: const Icon(Icons.print, color: Colors.black),
            label: const Text("Print & Clear", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12)),
          ),
        ],
      ),
    );
  }

  void _processClearTable(TableModel table, {bool printBill = false}) async {
    try {
      String? orderId = table.currentOrderId;
      if (orderId != null) {
        final orderDoc = await _firestore.collection('orders').doc(orderId).get();
        if (orderDoc.exists) {
          final orderData = orderDoc.data() as Map<String, dynamic>;
          if (printBill) await ReportService.printOrderReceipt(orderData, orderDoc.id);
          await _firestore.collection('orders').doc(orderId).update({
            'status': 'billed',
            'clearedAt': FieldValue.serverTimestamp(),
            'clearedBy': 'admin',
          });
          final kots = await _firestore.collection('kots').where('orderId', isEqualTo: orderId).get();
          for (final kot in kots.docs) {
            await kot.reference.update({'status': 'Served', 'clearedAt': FieldValue.serverTimestamp()});
          }
        }
      }
      await _firestore.collection('tables').doc(table.id).update({'status': TableStatus.available.name, 'currentOrderId': null});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  void _deleteSection(String id) => _firestore.collection('sections').doc(id).delete();

  void _showSectionDialog({String? restaurantId}) {
    final nameCtrl = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text("Add New Section", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFE7FF12).withOpacity(0.1))),
      content: Theme(
        data: ThemeData.dark().copyWith(
          inputDecorationTheme: InputDecorationTheme(
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE7FF12))),
          ),
        ),
        child: TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "e.g. Ground Floor")),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: () {
            if (nameCtrl.text.isNotEmpty) {
              _firestore.collection('sections').add({'name': nameCtrl.text.trim(), 'restaurantId': restaurantId});
              Navigator.pop(context);
            }
          }, 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
          child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ));
  }

  void _showTableDialog({TableModel? table, String? restaurantId}) {
    final nameCtrl = TextEditingController(text: table?.name);
    final capCtrl = TextEditingController(text: table?.capacity.toString() ?? '4');
    String? selectedSection = table?.section;

    showDialog(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(table == null ? "Create New Table" : "Edit Table", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFE7FF12).withOpacity(0.1))),
          content: Theme(
            data: ThemeData.dark().copyWith(
              inputDecorationTheme: InputDecorationTheme(
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE7FF12))),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Table Number/Name")),
                TextField(controller: capCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Capacity"), keyboardType: TextInputType.number),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('sections').where('restaurantId', isEqualTo: restaurantId).snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox();
                    final sections = snap.data!.docs;
                    return DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF2C2C2C),
                      value: sections.any((s) => s['name'] == selectedSection) ? selectedSection : null,
                      hint: const Text("Select Section", style: TextStyle(color: Colors.white54)),
                      items: sections.map((s) => DropdownMenuItem(value: s['name'].toString(), child: Text(s['name'], style: const TextStyle(color: Colors.white)))).toList(),
                      onChanged: (v) => setDialogState(() => selectedSection = v),
                      decoration: const InputDecoration(labelText: "Section"),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
            if (table != null)
              TextButton(onPressed: () { _firestore.collection('tables').doc(table.id).delete(); Navigator.pop(context); }, child: const Text("Delete", style: TextStyle(color: Colors.red))),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && selectedSection != null) {
                  final data = {
                    'name': nameCtrl.text.trim(),
                    'capacity': int.tryParse(capCtrl.text) ?? 4,
                    'section': selectedSection,
                    'status': table?.status.name ?? TableStatus.available.name,
                    'restaurantId': restaurantId,
                  };
                  if (table == null) {
                    _firestore.collection('tables').add(data);
                  } else {
                    _firestore.collection('tables').doc(table.id).update(data);
                  }
                  Navigator.pop(context);
                }
              }, 
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE7FF12), foregroundColor: Colors.black),
              child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    ));
  }
}
