import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/usb_printer_service.dart';
import '../../../services/bluetooth_printer_service.dart';
import '../../../services/report_service.dart';
import '../../../widgets/printer_settings_dialog.dart';
import '../../../utils/navigator_utils.dart';

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
        safePop(context);
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
              if (_selectedRole == 'waiter')
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance.collection('users')
                        .where('restaurantId', isEqualTo: context.read<AuthService>().restaurantId)
                        .where('role', isEqualTo: 'waiter')
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!.docs.length >= 2) {
                        return const Text(
                          "Max 2 Waiters limit reached for this restaurant.",
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => safePop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: _loading ? null : _create, 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFCDD22), foregroundColor: const Color(0xFF141615)),
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF141615))) : const Text("Create User", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

