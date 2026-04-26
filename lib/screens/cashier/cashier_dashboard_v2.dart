import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/pos_view_content.dart';
import './v2_styles.dart';
import '../../widgets/connectivity_indicators.dart';
import './reports_screen.dart';
import '../../utils/navigator_utils.dart';
import '../admin/bluetooth_printer_settings_screen.dart';
import '../admin/usb_printer_settings_screen.dart';
import '../admin/lan_printer_settings_screen.dart';

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
                      'assets/images/yugposlogo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(auth.restaurantName ?? "YUG POS", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  auth.currentEmail ?? "",
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
                _buildDrawerItem(Icons.dashboard_outlined, "Dashboard", true, () => Navigator.pop(context)),
                _buildDrawerItem(Icons.assessment_outlined, "Reports & History", false, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CashierReportsScreen()));
                }),
                _buildDrawerItem(Icons.print, "Printer Configuration", false, () {
                  Navigator.pop(context);
                  _showPrinterSelectionDialog();
                }),
                _buildDrawerItem(Icons.settings_outlined, "Settings", false, () {}),
                _buildDrawerItem(Icons.help_outline, "Support", false, () {}),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InkWell(
                    onTap: () => _showPrinterSelectionDialog(),
                    borderRadius: BorderRadius.circular(8),
                    child: const ConnectivityIndicators(),
                  ),
                ),
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
                        TextButton(onPressed: () => safePop(context, false), child: const Text("Cancel")),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          onPressed: () => safePop(context, true), 
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
            child: Text("v01.0-STABLE", style: TextStyle(color: Colors.white.withOpacity(0.1), fontSize: 9)),
          ),
        ],
      ),
    );
  }

  void _showPrinterSelectionDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141615),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "PRINTER CONFIGURATION",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            _buildPrinterTypeOption(
              icon: Icons.bluetooth,
              title: "Bluetooth Printers",
              subtitle: "Standard thermal printers via BT",
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const BluetoothPrinterSettingsScreen()));
              },
            ),
            _buildPrinterTypeOption(
              icon: Icons.usb,
              title: "USB Printers",
              subtitle: "Desktop or USB-OTG connection",
              color: const Color(0xFF3B9EFF),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const UsbPrinterSettingsScreen()));
              },
            ),
            _buildPrinterTypeOption(
              icon: Icons.lan,
              title: "LAN / Network Printers",
              subtitle: "IP-based printers on same WiFi",
              color: const Color(0xFFA78BFA),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const LanPrinterSettingsScreen()));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterTypeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
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
