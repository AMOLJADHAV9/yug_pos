import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../utils/navigator_utils.dart';

class BluetoothPrinterSettingsScreen extends StatefulWidget {
  const BluetoothPrinterSettingsScreen({super.key});

  @override
  State<BluetoothPrinterSettingsScreen> createState() => _BluetoothPrinterSettingsScreenState();
}

class _BluetoothPrinterSettingsScreenState extends State<BluetoothPrinterSettingsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Auto-scan on entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothPrinterService>().scan();
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final printerService = context.watch<BluetoothPrinterService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1110),
      appBar: AppBar(
        title: const Text("PRINTER SETTINGS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (printerService.isScanning)
            RotationTransition(
              turns: _scanController,
              child: const IconButton(
                icon: Icon(Icons.sync, color: Color(0xFFFCDD22)),
                onPressed: null,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFFFCDD22)),
              onPressed: () => printerService.scan(),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBanner(printerService),
          Expanded(
            child: printerService.devices.isEmpty && !printerService.isScanning
                ? _buildEmptyState(printerService)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: printerService.devices.length,
                    itemBuilder: (context, index) {
                      final device = printerService.devices[index];
                      final isSelected = printerService.selectedDevice?.address == device.address;
                      return _buildDeviceCard(device, isSelected, printerService);
                    },
                  ),
          ),
          if (printerService.isConnected) _buildTestPrintFooter(printerService),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(BluetoothPrinterService service) {
    Color statusColor = Colors.redAccent;
    String statusText = "DISCONNECTED";
    IconData statusIcon = Icons.bluetooth_disabled;

    if (service.isConnected) {
      statusColor = Colors.greenAccent;
      statusText = "CONNECTED: ${service.selectedDevice?.name ?? 'PRINTER'}";
      statusIcon = Icons.bluetooth_connected;
    } else if (service.isConnecting) {
      statusColor = Colors.orangeAccent;
      statusText = "CONNECTING...";
      statusIcon = Icons.bluetooth_searching;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        border: Border(bottom: BorderSide(color: statusColor.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 12),
          Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BluetoothPrinterService service) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.print_disabled, size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text("No Bluetooth Printers Found", style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => service.scan(),
            icon: const Icon(Icons.search),
            label: const Text("SCAN AGAIN"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFCDD22),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(PrinterDevice device, bool isSelected, BluetoothPrinterService service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFCDD22).withOpacity(0.08) : const Color(0xFF1A1C1B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFFFCDD22).withOpacity(0.5) : Colors.white.withOpacity(0.05),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFCDD22) : Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.print,
            color: isSelected ? Colors.black : Colors.white38,
            size: 20,
          ),
        ),
        title: Text(
          device.name ?? "Unknown Device",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          device.address ?? "No Address",
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Color(0xFFFCDD22))
            : Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2)),
        onTap: () async {
          if (isSelected) {
            _showDisconnectSheet(context, service);
          } else {
            final success = await service.connect(device.address!, name: device.name);
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Printer connected successfully!"), backgroundColor: Colors.green),
              );
            }
          }
        },
      ),
    );
  }

  void _showDisconnectSheet(BuildContext context, BluetoothPrinterService service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1C1B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text("Manage Printer", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(service.selectedDevice?.name ?? "Selected Printer", style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 32),
            ListTile(
              leading: const Icon(Icons.bluetooth_disabled, color: Colors.redAccent),
              title: const Text("Disconnect & Forget", style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                service.disconnect();
                safePop(context);
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => safePop(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.white.withOpacity(0.05),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("CANCEL"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestPrintFooter(BluetoothPrinterService service) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C1B),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => service.testPrint(),
            icon: const Icon(Icons.text_fields),
            label: const Text("PRINT TEST PAGE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFCDD22),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}
