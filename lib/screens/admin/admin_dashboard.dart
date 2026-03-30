import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../utils/debouncer.dart';
import 'tabs/revenue_tab.dart';
import 'tabs/users_tab.dart';
import 'tabs/menu_tab.dart';
import 'tabs/tables_tab.dart';
import 'tabs/orders_tab.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/takeaway_tab.dart';
import '../order/online_orders_screen.dart';
import '../home/tables_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  bool _isExtended = true;
  final _debouncer = Debouncer(milliseconds: 1500);
  String? _currentRestaurantId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    if (_currentRestaurantId != auth.restaurantId) {
      _currentRestaurantId = auth.restaurantId;
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }


  void _showMonthSelectionDialog() {
    int selectedYear = DateTime.now().year;
    int selectedMonth = DateTime.now().month;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFE7FF12).withOpacity(0.1))),
          title: const Text("Download Monthly Report", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select the month and year for the report:", style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Theme(
                data: Theme.of(context).copyWith(canvasColor: const Color(0xFF1E1E1E)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    DropdownButton<int>(
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Color(0xFFE7FF12)),
                      value: selectedYear,
                      items: List.generate(5, (i) => DateTime.now().year - i)
                          .map((y) => DropdownMenuItem(value: y, child: Text(y.toString())))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedYear = v!),
                    ),
                    DropdownButton<int>(
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Color(0xFFE7FF12)),
                      value: selectedMonth,
                      items: List.generate(12, (i) => i + 1)
                          .map((m) => DropdownMenuItem(value: m, child: Text(DateFormat('MMMM').format(DateTime(2022, m)))))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedMonth = v!),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE7FF12),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(context);
                _generateMonthlyReport(selectedYear, selectedMonth);
              },
              child: const Text("Download PDF", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateDailyReport() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final restaurantId = context.read<AuthService>().restaurantId;
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

      final snapshot = await FirebaseFirestore.instance.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .where('createdAt', isLessThanOrEqualTo: endOfDay)
          .get();
      
      if (mounted) Navigator.pop(context);
      
      if (snapshot.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No records available for today")));
        return;
      }

      final orders = snapshot.docs.toList();
      final dateStr = DateFormat('dd MMM yyyy').format(today);
      await ReportService.generatePeriodReport("Daily Revenue Report", "Date: $dateStr", orders, restaurantName: context.read<AuthService>().restaurantName ?? "YUG POS");
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching records: $e")));
      }
    }
  }

  Future<void> _generateMonthlyReport(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
    final monthName = DateFormat('MMMM yyyy').format(startOfMonth);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final restaurantId = context.read<AuthService>().restaurantId;
      final snapshot = await FirebaseFirestore.instance.collection('orders')
          .where('restaurantId', isEqualTo: restaurantId)
          .get();
      
      final orders = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // We want to show everything in the report, but usually only billed/active.
        // For a revenue report, we strictly want billed. 
        if (data['status'] == 'cancelled') return false;
        if (data['createdAt'] == null) return false;
        
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        return createdAt.isAfter(startOfMonth.subtract(const Duration(seconds: 1))) && 
               createdAt.isBefore(endOfMonth.add(const Duration(seconds: 1)));
      }).toList();
      
      if (mounted) Navigator.pop(context);
      
      if (orders.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No records available for $monthName")));
        return;
      }

      await ReportService.generatePeriodReport("Monthly Revenue Report", "Period: $monthName", orders, restaurantName: context.read<AuthService>().restaurantName ?? "YUG POS");
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching records: $e")));
      }
    }
  }

  late final List<Widget> _tabs = [
    RevenueTab(onTabRequested: (index) => setState(() => _selectedIndex = index)),
    const TablesScreen(isTab: true),
    const AnalyticsTab(),
    const UsersTab(),
    const MenuTab(),
    const TablesTab(),
    const OrdersTab(),
    const TakeawayTab(),
    const OnlineOrdersScreen(isTab: true),
  ];

  static const _navData = [
    {'icon': Icons.dashboard, 'label': 'Dashboard'},
    {'icon': Icons.point_of_sale, 'label': 'POS'},
    {'icon': Icons.analytics, 'label': 'Analytics'},
    {'icon': Icons.people, 'label': 'Staff'},
    {'icon': Icons.restaurant_menu, 'label': 'Menu'},
    {'icon': Icons.table_bar, 'label': 'Tables'},
    {'icon': Icons.receipt_long, 'label': 'Orders'},
    {'icon': Icons.shopping_bag, 'label': 'Takeaway'},
    {'icon': Icons.cloud_download, 'label': 'Online'},
  ];

  // Specific indices for the Bottom Navbar
  static const List<int> _bottomBarIndices = [0, 1, 3, 4, 6];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: Text(_navData[_selectedIndex]['label'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.black,
              elevation: 0,
              iconTheme: IconThemeData(color: theme.colorScheme.primary),
              actions: [
                const SizedBox(width: 8),
              ],
            ),
            drawer: Drawer(
              child: Column(
                children: [
                   DrawerHeader(
                    decoration: const BoxDecoration(color: Colors.black),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restaurant, size: 48, color: const Color(0xFFE7FF12)),
                          const SizedBox(height: 10),
                          const Text("YUG POS", style: TextStyle(color: Color(0xFFE7FF12), fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        ...List.generate(_navData.length, (index) {
                          final item = _navData[index];
                          final isSelected = _selectedIndex == index;
                          return ListTile(
                            leading: Icon(item['icon'] as IconData, color: isSelected ? const Color(0xFFE7FF12) : Colors.grey),
                            title: Text(item['label'] as String, style: TextStyle(color: isSelected ? const Color(0xFFE7FF12) : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            selected: isSelected,
                            onTap: () {
                              setState(() => _selectedIndex = index);
                              Navigator.pop(context);
                            },
                          );
                        }),
                        const Divider(color: Colors.white10),
                        const Padding(
                          padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                          child: Text("REPORTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        ListTile(
                          leading: const Icon(Icons.today, color: Color(0xFFE7FF12)),
                          title: const Text("Daily Report", style: TextStyle(color: Colors.white70)),
                          onTap: () {
                            Navigator.pop(context);
                            _generateDailyReport();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.summarize, color: Color(0xFFE7FF12)),
                          title: const Text("Monthly Report", style: TextStyle(color: Colors.white70)),
                          onTap: () {
                            Navigator.pop(context);
                            _showMonthSelectionDialog();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
                    onTap: () => context.read<AuthService>().logout(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            body: IndexedStack(index: _selectedIndex, children: _tabs),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _bottomBarIndices.contains(_selectedIndex) 
                ? _bottomBarIndices.indexOf(_selectedIndex) 
                : 0,
              onTap: (idx) => setState(() => _selectedIndex = _bottomBarIndices[idx]),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: theme.colorScheme.primary,
              unselectedItemColor: Colors.grey,
              backgroundColor: Colors.black,
              items: _bottomBarIndices.map((i) => BottomNavigationBarItem(
                icon: Icon(_navData[i]['icon'] as IconData), 
                label: _navData[i]['label'] as String
              )).toList(),
            ),
          );
        }

        // Desktop: Custom Animated Sidebar
        return Scaffold(
          body: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _isExtended ? 240 : 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
                ),
                child: Column(
                  children: [
                    // Header with Toggle
                    Container(
                      height: 80,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: _isExtended ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
                        children: [
                          if (_isExtended)
                            const Expanded(
                              child: Text("YUG POS", 
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFE7FF12)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          IconButton(
                            icon: Icon(_isExtended ? Icons.menu_open : Icons.menu),
                            onPressed: () => setState(() => _isExtended = !_isExtended),
                            color: Colors.grey[700],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Nav Items
                    Expanded(
                      child: ListView(
                        children: [
                          ...List.generate(_navData.length, (index) {
                            final item = _navData[index];
                            final isSelected = _selectedIndex == index;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: InkWell(
                                onTap: () => setState(() => _selectedIndex = index),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                    children: [
                                      Icon(item['icon'] as IconData, color: isSelected ? theme.colorScheme.primary : Colors.grey[600], size: 24),
                                      if (_isExtended) ...[
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            item['label'] as String,
                                            style: TextStyle(
                                              color: isSelected ? theme.colorScheme.primary : Colors.grey[400],
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const Divider(),
                          if (_isExtended)
                            const Padding(
                              padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                              child: Text("REPORTS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1)),
                            )
                          else
                            const SizedBox(height: 16),
                          
                          
                          // Daily Report Button
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: InkWell(
                              onTap: _generateDailyReport,
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.file_download, color: Color(0xFFE7FF12), size: 24),
                                    if (_isExtended) ...[
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text("Daily Report", 
                                          style: TextStyle(color: Colors.white70, fontSize: 13),
                                          overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Monthly Report Button
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: InkWell(
                              onTap: () => _showMonthSelectionDialog(),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.summarize, color: Color(0xFFE7FF12), size: 24),
                                    if (_isExtended) ...[
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text("Monthly Report", 
                                          style: TextStyle(color: Colors.white70, fontSize: 13),
                                          overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Footer
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: InkWell(
                        onTap: () => context.read<AuthService>().logout(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.logout, color: Colors.redAccent),
                              if (_isExtended) ...[
                                const SizedBox(width: 12),
                                const Flexible(child: Text("Logout", 
                                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                )),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: IndexedStack(index: _selectedIndex, children: _tabs),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
