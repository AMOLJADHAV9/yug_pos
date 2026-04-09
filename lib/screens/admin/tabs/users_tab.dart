import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/usb_printer_service.dart';
import '../../../services/bluetooth_printer_service.dart';
import '../../../services/report_service.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final restaurantId = context.watch<AuthService>().restaurantId;

    if (restaurantId == null) {
      return const Scaffold(
        backgroundColor: const Color(0xFF141615),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      body: kIsWeb 
        ? FutureBuilder<QuerySnapshot>(
            future: _firestore.collection('users').where('restaurantId', isEqualTo: restaurantId).get(),
            builder: (context, snapshot) => _buildUsersContent(context, snapshot, restaurantId),
          )
        : StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').where('restaurantId', isEqualTo: restaurantId).snapshots(),
            builder: (context, snapshot) => _buildUsersContent(context, snapshot, restaurantId),
          ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "admin_users_fab",
        onPressed: () => _showAddUserDialog(context),
        icon: const Icon(Icons.person_add_alt_1, color: const Color(0xFF141615)),
        label: const Text("Add Staff Member", style: TextStyle(color: const Color(0xFF141615), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFCDD22),
      ),
    );
  }

  Widget _buildUsersContent(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot, String? restaurantId) {
    if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.white54)));
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    
    final users = snapshot.data?.docs ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row / Column
              if (isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text("Staff Management", 
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFFFCDD22)),
                          onPressed: () => setState(() {}),
                          tooltip: "Refresh Staff",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Staff Management", 
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Color(0xFFFCDD22)),
                      onPressed: () => setState(() {}),
                      tooltip: "Refresh Staff",
                    ),
                  ],
                ),
              const SizedBox(height: 32),
              
              _buildSectionHeader("Staff Members List", Icons.people, Colors.blue),
              const SizedBox(height: 16),

              // Responsive List Layout
              if (isMobile)
                _buildStaffMobileList(users, context)
              else
                _buildStaffDesktopTable(users, context),
              
              const SizedBox(height: 40),
            ],
          ),
        );
      }
    );
  }

  Widget _buildStaffMobileList(List<QueryDocumentSnapshot> users, BuildContext context) {
    if (users.isEmpty) return const Center(child: Text("No staff members found."));

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: users.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final data = users[index].data() as Map<String, dynamic>;
        final role = data['role'] ?? 'waiter';
        final status = data['status'] ?? 'active';
        final name = data['name'] ?? 'N/A';
        final email = data['email'] ?? 'N/A';
        final uid = users[index].id;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141615),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    ),
                    _buildStatusChip(status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildRoleChip(role.toString()),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.mail_outline, size: 20, color: Colors.blue),
                          onPressed: () => _sendResetEmail(context, email),
                          tooltip: "Reset Password",
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                        if (uid != context.read<AuthService>().currentUser?.uid)
                          IconButton(
                            icon: Icon(
                              status == 'active' ? Icons.block : Icons.check_circle_outline, 
                              size: 20, 
                              color: status == 'active' ? Colors.red : Colors.green
                            ),
                            onPressed: () => _toggleUserStatus(context, uid, status == 'active'),
                            tooltip: status == 'active' ? "Disable User" : "Enable User",
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaffDesktopTable(List<QueryDocumentSnapshot> users, BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 48),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(const Color(0xFF2C2C2C)),
              dataRowColor: MaterialStateProperty.all(const Color(0xFF141615)),
              horizontalMargin: 24,
              columnSpacing: 40,
              dataRowHeight: 64,
              columns: const [
                DataColumn(label: Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70))),
                DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70))),
                DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70))),
                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70))),
              ],
              rows: users.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final role = data['role'] ?? 'waiter';
                final status = data['status'] ?? 'active';
                final name = data['name'] ?? 'N/A';
                final email = data['email'] ?? 'N/A';
                final uid = doc.id;

                final currentUserUid = context.read<AuthService>().currentUser?.uid;

                return DataRow(cells: [
                  DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
                  DataCell(Text(email, style: const TextStyle(color: Colors.white70))),
                  DataCell(_buildRoleChip(role.toString())),
                  DataCell(_buildStatusChip(status)),
                  DataCell(
                    SizedBox(
                      width: 100,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.mail_outline, size: 20, color: Color(0xFFFCDD22)),
                            onPressed: () => _sendResetEmail(context, email),
                            tooltip: "Reset Password",
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: Icon(
                              status == 'active' ? Icons.block : Icons.check_circle_outline, 
                              size: 20, 
                              color: status == 'active' ? Colors.redAccent : const Color(0xFFFCDD22)
                            ),
                            onPressed: () => _toggleUserStatus(context, uid, status == 'active'),
                            tooltip: status == 'active' ? "Disable User" : "Enable User",
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFFCDD22).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: const Color(0xFFFCDD22), size: 18),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1)),
      ],
    );
  }

  Widget _buildRoleChip(String role) {
    Color color = const Color(0xFFFCDD22);
    if (role == 'admin') color = Colors.purpleAccent;
    if (role == 'cashier') color = Colors.orangeAccent;
    

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(role.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatusChip(String status) {
    bool active = status == 'active';
    Color color = active ? const Color(0xFFFCDD22) : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(active ? "ACTIVE" : "DISABLED", style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _showAddUserDialog(BuildContext context) {
     showDialog(context: context, builder: (_) => const AddUserDialog());
  }

  void _toggleUserStatus(BuildContext context, String uid, bool curActive) async {
    await context.read<AuthService>().updateStaffStatus(uid, !curActive);
  }

  void _sendResetEmail(BuildContext context, String email) async {
    await context.read<AuthService>().sendResetEmail(email);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reset email sent!")));
  }

  void _showPrinterSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PrinterSettingsDialog(),
    );
  }
}

class AddUserDialog extends StatefulWidget {
  const AddUserDialog({super.key});

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _selectedRole = 'waiter';
  bool _loading = false;

  void _create() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final error = await context.read<AuthService>().adminCreateUser(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      role: _selectedRole,
      phone: _phoneCtrl.text.trim(),
      pin: _pinCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _loading = false);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Staff user created successfully!"), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF141615),
      title: const Text("Register New Staff Member", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFFFCDD22).withOpacity(0.1))),
      content: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          inputDecorationTheme: InputDecorationTheme(
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFCDD22))),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Full Name")),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: "Email")),
              TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: "Assign Password"), obscureText: true),
              TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: "Phone (Optional)")),
              TextField(controller: _pinCtrl, decoration: const InputDecoration(labelText: "Login PIN (4 digits)"), maxLength: 4, keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF2C2C2C),
                value: _selectedRole,
                items: ['waiter', 'cashier', 'admin'].map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase(), style: const TextStyle(color: Colors.white)))).toList(),
                onChanged: (v) => setState(() => _selectedRole = v!),
                decoration: const InputDecoration(labelText: "Assign Role"),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: _loading ? null : _create, 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFCDD22), foregroundColor: const Color(0xFF141615)),
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF141615))) : const Text("Create User", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class PrinterSettingsDialog extends StatefulWidget {
  const PrinterSettingsDialog({super.key});

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _tabCount;

  @override
  void initState() {
    super.initState();
    final bool showBluetooth = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    _tabCount = showBluetooth ? 2 : 1;
    _tabController = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF141615),
      titlePadding: EdgeInsets.zero,
      title: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                const Icon(Icons.print, color: Color(0xFFFCDD22)),
                const SizedBox(width: 10),
                const Text("Printer Configuration", style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFCDD22),
            labelColor: const Color(0xFFFCDD22),
            unselectedLabelColor: Colors.white54,
            tabs: [
              const Tab(text: "USB (Windows)", icon: Icon(Icons.usb, size: 20)),
              if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) 
                const Tab(text: "Bluetooth (Android)", icon: Icon(Icons.bluetooth, size: 20)),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildUsbTab(),
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) 
              _buildBluetoothTab(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CLOSE", style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _buildUsbTab() {
    return Consumer<UsbPrinterService>(
      builder: (context, service, _) {
        return Column(
          children: [
            const SizedBox(height: 16),
            if (service.selectedDevice != null) ...[
              _buildConnectedSourceCard(
                name: service.selectedDevice!.name ?? "USB Printer",
                address: service.selectedDevice!.address ?? "USB",
                isConnected: service.isConnected,
                onForget: () => service.disconnect(),
                onTest: () async {
                  final bytes = await ReportService.generateKOTBytes({
                    'tableName': 'TEST-USB', 
                    'items': [{'name': 'USB TEST PRINT', 'quantity': 1}]
                  });
                  await service.printRawBytes(bytes);
                },
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: _buildDeviceList(
                devices: service.devices,
                isScanning: service.isScanning,
                onScan: () => service.scan(),
                onSelect: (d) => service.selectDevice(d),
                emptyTitle: "No USB printers found",
                helpText: "Select a USB printer below:",
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBluetoothTab() {
    return Consumer<BluetoothPrinterService>(
      builder: (context, service, _) {
        return Column(
          children: [
            const SizedBox(height: 16),
            if (service.selectedDevice != null || service.hasSavedPrinter) ...[
              _buildConnectedSourceCard(
                name: service.selectedDevice?.name ?? "Saved Printer",
                address: service.selectedDevice?.address ?? "",
                isConnected: service.isConnected,
                onForget: () => service.disconnect(),
                onTest: () async {
                  final bytes = await ReportService.generateKOTBytes({
                    'tableName': 'TEST-BT', 
                    'items': [{'name': 'BLUETOOTH TEST', 'quantity': 1}]
                  }, paperSize: PaperSize.mm58);
                  final success = await service.printRawBytes(bytes);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(success ? "Test Page Sent!" : "Failed to print"),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ));
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: _buildDeviceList(
                devices: service.devices,
                isScanning: service.isScanning,
                onScan: () => service.scan(),
                onSelect: (d) => service.selectDevice(d),
                emptyTitle: "No Bluetooth printers found",
                helpText: "Select a paired Bluetooth printer:",
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConnectedSourceCard({
    required String name,
    required String address,
    required bool isConnected,
    required VoidCallback onForget,
    required VoidCallback onTest,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFCDD22).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCDD22).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(isConnected ? Icons.check_circle : Icons.error_outline, 
                   color: isConnected ? Colors.greenAccent : Colors.redAccent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isConnected ? "CONNECTED" : "DISCONNECTED", 
                         style: TextStyle(color: isConnected ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (address.isNotEmpty) Text(address, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onForget, child: const Text("FORGET", style: TextStyle(color: Colors.redAccent, fontSize: 11))),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onTest, 
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFCDD22), minimumSize: const Size(80, 32)),
                child: const Text("TEST PRINT", style: TextStyle(color: Color(0xFF141615), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList({
    required List<dynamic> devices,
    required bool isScanning,
    required VoidCallback onScan,
    required Function(dynamic) onSelect,
    required String emptyTitle,
    required String helpText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(helpText, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (isScanning)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFCDD22)))
            else
              IconButton(onPressed: onScan, icon: const Icon(Icons.refresh, size: 18, color: Color(0xFFFCDD22))),
          ],
        ),
        const SizedBox(height: 8),
        if (!isScanning && devices.isEmpty)
          Expanded(child: Center(child: Text(emptyTitle, style: const TextStyle(color: Colors.white38))))
        else
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final d = devices[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.name ?? "Unknown Device", style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(d.address ?? "", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                  onTap: () => onSelect(d),
                );
              },
            ),
          ),
      ],
    );
  }
}
