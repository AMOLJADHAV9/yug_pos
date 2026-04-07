import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/pos_view_content.dart';
import './v2_styles.dart';
import './reports_screen.dart';

class CashierDashboardV2 extends StatefulWidget {
  const CashierDashboardV2({super.key});

  @override
  State<CashierDashboardV2> createState() => _CashierDashboardV2State();
}

class _CashierDashboardV2State extends State<CashierDashboardV2> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 1200;
        
        if (isMobile) {
          // Inner POSViewContent handles everything on mobile (including its own Scaffold & Drawer)
          return const POSViewContent(isAdminTab: false);
        }
        
        // Desktop uses the outer Scaffold with Drawer
        final auth = context.watch<AuthService>();
        return Scaffold(
          backgroundColor: V2Colors.bg,
          drawer: _buildDrawer(context, auth),
          body: const SafeArea(
            child: POSViewContent(isAdminTab: false),
          ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, AuthService auth) {
    return Drawer(
      backgroundColor: const Color(0xFF0E0E0E),
      elevation: 0,
      width: 280,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF000000),
              border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 132,
                    height: 46,
                    child: Image.asset(
                      'lib/assets/img/yug-poslogo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(auth.restaurantName ?? "YUG POS", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  auth.currentUser?.email ?? "",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: V2Colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _buildDrawerItem(Icons.dashboard_outlined, "Dashboard", true, () => Scaffold.of(context).closeDrawer()),
                _buildDrawerItem(Icons.assessment_outlined, "Reports & History", false, () {
                  Scaffold.of(context).closeDrawer();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CashierReportsScreen()));
                }),
                _buildDrawerItem(Icons.settings_outlined, "Settings", false, () {}),
                _buildDrawerItem(Icons.help_outline, "Support", false, () {}),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1A1A1A), height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: Colors.red.withOpacity(0.08),
                leading: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                title: const Text("Logout", style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                dense: true,
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: V2Colors.s1,
                      title: const Text("Logout?", style: TextStyle(color: Colors.white, fontSize: 16)),
                      content: const Text("Are you sure you want to end your session?", style: TextStyle(color: V2Colors.muted, fontSize: 13)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(context, true), 
                          child: const Text("Logout")
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await auth.logout();
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text("v2.1.0-STABLE", style: TextStyle(color: Colors.white.withOpacity(0.1), fontSize: 9)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String label, bool isSelected, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selected: isSelected,
        selectedTileColor: V2Colors.yellow.withOpacity(0.05),
        leading: Icon(icon, size: 20, color: isSelected ? V2Colors.yellow : V2Colors.muted),
        title: Text(label, style: TextStyle(
          color: isSelected ? V2Colors.yellow : Colors.white70,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
        )),
        dense: true,
      ),
    );
  }
}
