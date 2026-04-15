import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../../services/bluetooth_printer_service.dart';
import '../../../screens/cashier/v2_styles.dart';
import '../../../utils/navigator_utils.dart';

class BluetoothSettingsTab extends StatefulWidget {
  const BluetoothSettingsTab({super.key});

  @override
  State<BluetoothSettingsTab> createState() => _BluetoothSettingsTabState();
}

class _BluetoothSettingsTabState extends State<BluetoothSettingsTab> with SingleTickerProviderStateMixin {
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

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Bluetooth Printer",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    printerService.isConnected 
                        ? "Connected to: ${printerService.selectedDevice?.name ?? 'Unknown'}" 
                        : (printerService.isConnecting ? "Connecting..." : "Not connected"),
                    style: TextStyle(color: printerService.isConnected ? V2Colors.yellow : V2Colors.muted, fontSize: 13),
                  ),
                ],
              ),
              IconButton.filled(
                onPressed: printerService.isScanning ? null : () => printerService.scan(),
                icon: printerService.isScanning 
                    ? RotationTransition(
                        turns: _scanController,
                        child: const Icon(Icons.sync, color: Colors.black, size: 20),
                      )
                    : const Icon(Icons.refresh, color: Colors.black, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: V2Colors.yellow,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildStatusBanner(printerService),
          const SizedBox(height: 16),
          Expanded(
            child: printerService.devices.isEmpty && !printerService.isScanning
                ? _buildEmptyState(printerService)
                : ListView.builder(
                    padding: EdgeInsets.zero,
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
    Color statusColor = V2Colors.red;
    String statusText = "DISCONNECTED";
    IconData statusIcon = Icons.bluetooth_disabled;

    if (service.isConnected) {
      statusColor = V2Colors.green;
      statusText = "CONNECTED: ${service.selectedDevice?.name ?? 'PRINTER'}";
      statusIcon = Icons.bluetooth_connected;
    } else if (service.isConnecting) {
      statusColor = V2Colors.orange;
      statusText = "CONNECTING...";
      statusIcon = Icons.bluetooth_searching;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 18),
          const SizedBox(width: 12),
          Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
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
          Icon(Icons.print_disabled, size: 48, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text("No Bluetooth Printers Found", style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => service.scan(),
            icon: const Icon(Icons.search, size: 18),
            label: const Text("SCAN AGAIN"),
            style: TextButton.styleFrom(
              foregroundColor: V2Colors.yellow,
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
        color: isSelected ? V2Colors.yellow.withOpacity(0.05) : V2Colors.s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? V2Colors.yellow.withOpacity(0.3) : V2Colors.border,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isCurrentDevice(device, service) ? V2Colors.yellow : Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.print,
            color: isCurrentDevice(device, service) ? Colors.black : Colors.white38,
            size: 20,
          ),
        ),
        title: Text(
          device.name ?? "Unknown Device",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          device.address ?? "No Address",
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: V2Colors.yellow, size: 20)
            : const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
        onTap: () async {
          if (isSelected) {
            _showDisconnectSheet(context, service);
          } else {
            final success = await service.connect(device.address!, name: device.name);
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Printer connected successfully!"), backgroundColor: V2Colors.green),
              );
            }
          }
        },
      ),
    );
  }

  bool isCurrentDevice(PrinterDevice device, BluetoothPrinterService service) {
    return service.selectedDevice?.address == device.address;
  }

  void _showDisconnectSheet(BuildContext context, BluetoothPrinterService service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: V2Colors.s1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Manage Printer", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(service.selectedDevice?.name ?? "Selected Printer", style: const TextStyle(color: V2Colors.muted, fontSize: 13)),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.bluetooth_disabled, color: V2Colors.red),
              title: const Text("Disconnect & Forget", style: TextStyle(color: V2Colors.red)),
              onTap: () {
                service.disconnect();
                safePop(context);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => safePop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: V2Colors.s2,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("CANCEL"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestPrintFooter(BluetoothPrinterService service) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      child: ElevatedButton.icon(
        onPressed: () => service.testPrint(),
        icon: const Icon(Icons.text_fields, size: 18),
        label: const Text("PRINT TEST PAGE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        style: ElevatedButton.styleFrom(
          backgroundColor: V2Colors.yellow,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
