import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../../services/kot_notification_service.dart';
import '../../utils/debouncer.dart';
import '../kot/kot_tracking_screen.dart';
import '../order/order_summary_screen.dart';
import '../order/menu_screen.dart';
import '../order/takeaway_list_screen.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  int _currentIndex = 0;
  final KotNotificationService _kotService = KotNotificationService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final restaurantId = context.read<AuthService>().restaurantId;
    if (restaurantId != null) {
      _kotService.startListening(restaurantId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          TablesGridTab(),
          KotTrackingScreen(),
          TakeawayListScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (val) => setState(() => _currentIndex = val),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.table_restaurant), label: 'Tables'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'KOTs'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag), label: 'Takeaway'),
        ],
      ),
    );
  }
}

class TablesGridTab extends StatefulWidget {
  const TablesGridTab({super.key});

  @override
  State<TablesGridTab> createState() => _TablesGridTabState();
}

class _TablesGridTabState extends State<TablesGridTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _debouncer = Debouncer(milliseconds: 1000);
  String _selectedSection = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tables', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StreamBuilder<void>(
              stream: FirebaseFirestore.instance.snapshotsInSync(),
              builder: (context, _) => FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('tables')
                    .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
                    .limit(1).get(const GetOptions(source: Source.server)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
                  if (snapshot.hasError) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(4)),
                      child: const Text("OFFLINE", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthService>().logout();
            },
          )
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildGrid()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPinSetupDialog(),
        tooltip: 'Set PIN',
        child: const Icon(Icons.dialpad),
      ),
    );
  }

  Future<void> _showPinSetupDialog() async {
    final auth = context.read<AuthService>();
    if (auth.hasSavedPin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN already set')));
      return;
    }
    String pin = '';
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set 4-Digit PIN'),
          content: TextField(
            maxLength: 4,
            keyboardType: TextInputType.number,
            obscureText: true,
            onChanged: (val) => pin = val,
            decoration: const InputDecoration(hintText: 'Enter 4 digits'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')
            ),
            ElevatedButton(
              onPressed: () {
                if (pin.length == 4) {
                  auth.savePin(pin);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN Saved!')));
                }
              },
              child: const Text('Save')
            )
          ]
        );
      }
    );
  }

  Widget _buildFilters() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        final List<String> sections = ['All'];
        if (snapshot.hasData) {
          final uniqueSections = snapshot.data!.docs
              .map((doc) => doc.data() as Map<String, dynamic>)
              .map((data) => data['section'] as String?)
              .where((s) => s != null)
              .cast<String>()
              .toSet();
          sections.addAll(uniqueSections);
        }

        return SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final text = sections[index];
              final isSelected = _selectedSection == text;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 12, bottom: 12),
                child: ChoiceChip(
                  label: Text(text, style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.black : Colors.white70
                  )),
                  selected: isSelected,
                  selectedColor: const Color(0xFFE7FF12),
                  backgroundColor: const Color(0xFF1E1E1E),
                  onSelected: (val) {
                    if (val) setState(() => _selectedSection = text);
                  },
                ),
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildGrid() {
    final restaurantId = context.read<AuthService>().restaurantId;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('tables').where('restaurantId', isEqualTo: restaurantId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final tables = snapshot.data!.docs.map((doc) {
          return TableModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        }).where((t) => _selectedSection == 'All' || t.section == _selectedSection).toList();

        if (tables.isEmpty) {
          return const Center(child: Text('No tables found'));
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount = 4; // Increased from 3 to 4 for ultra-compact mobile
            if (constraints.maxWidth > 1200) {
              crossAxisCount = 8; // Increased for desktop too
            } else if (constraints.maxWidth > 900) {
              crossAxisCount = 6;
            } else if (constraints.maxWidth > 600) {
              crossAxisCount = 4;
            }

            return GridView.builder(
              padding: const EdgeInsets.all(8), // Even smaller padding
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8, // Even smaller spacing
                mainAxisSpacing: 8,
                childAspectRatio: 0.9, // Taller to fit vertical stack
              ),
              itemCount: tables.length,
              itemBuilder: (context, index) {
                return _buildTableCard(tables[index]);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTableCard(TableModel table) {
    Color statusColor;
    String statusStr;
    switch (table.status) {
      case TableStatus.available:
        statusColor = Colors.red;
        statusStr = 'Available';
        break;
      case TableStatus.occupied:
        statusColor = Colors.green;
        statusStr = 'Occupied';
        break;
      case TableStatus.kotSent:
        statusColor = Colors.green;
        statusStr = 'KOT Sent';
        break;
      case TableStatus.billRequested:
        statusColor = Colors.green;
        statusStr = 'Bill Requested';
        break;
    }

    return InkWell(
      onTap: () {
        _debouncer.run(() => _handleTableTap(table));
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: table.status == TableStatus.available ? Colors.transparent : statusColor, 
            width: 1.5
          ),
          boxShadow: [
            if (table.status != TableStatus.available)
              BoxShadow(
                color: statusColor.withOpacity(0.2), 
                blurRadius: 8, 
                offset: const Offset(0, 2)
              )
          ]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(table.name, style: TextStyle(
              fontSize: 15, 
              fontWeight: FontWeight.bold,
              color: table.status == TableStatus.available ? Colors.white : statusColor
            )),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusStr,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 9),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text('${table.capacity}p', style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _handleTableTap(TableModel table) {
    if (table.status == TableStatus.available) {
      final nameController = TextEditingController();
      final phoneController = TextEditingController();
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text("Start order for ${table.name}?",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Customer Name",
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE7FF12))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Contact Number",
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE7FF12))),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white54))),
                ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final cart = context.read<CartProvider>();
                      cart.setTable(table.id);
                      cart.setCustomerInfo(nameController.text,
                          phone: phoneController.text);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => MenuScreen(
                                    table: table,
                                    customerName: nameController.text.isEmpty
                                        ? "Walk-in"
                                        : nameController.text,
                                    customerPhone: phoneController.text,
                                  )));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE7FF12),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirm',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ]));
    } else {
      if (table.currentOrderId != null) {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => OrderSummaryScreen(
                    table: table, orderId: table.currentOrderId!)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error: No active order found on this table')));
      }
    }
  }
}
