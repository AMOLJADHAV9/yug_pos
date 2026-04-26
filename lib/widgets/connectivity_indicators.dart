import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/wifi_service.dart';
import '../models/printer_role.dart';
import '../screens/cashier/v2_styles.dart';

class ConnectivityIndicators extends StatelessWidget {
  const ConnectivityIndicators({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Consumer<BluetoothPrinterService>(
            builder: (context, bt, _) => _buildBluetoothIndicator(context, bt),
          ),
          const SizedBox(height: 8),
          _buildWifiStatus(context),
        ],
      ),
    );
  }

  Widget _buildBluetoothIndicator(BuildContext context, BluetoothPrinterService bt) {
    final hasKot = bt.hasRolePrinter(PrinterRole.kot);
    final hasBill = bt.hasRolePrinter(PrinterRole.bill);
    final isConnected = bt.isConnected;

    String statusText = "No Printer";
    Color statusColor = V2Colors.muted;
    IconData icon = Icons.bluetooth_disabled;

    if (hasKot && hasBill) {
      statusText = "KOT & Bill OK";
      statusColor = isConnected ? V2Colors.green : V2Colors.yellow;
      icon = Icons.bluetooth_connected;
    } else if (hasKot || hasBill) {
      statusText = hasKot ? "KOT Only" : "Bill Only";
      statusColor = V2Colors.orange;
      icon = Icons.bluetooth;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: statusColor),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildWifiStatus(BuildContext context) {
    return Consumer<WifiService>(
      builder: (context, wifi, _) {
        final isSupported = !kIsWeb && Platform.isAndroid;
        final isConnected = wifi.isConnected;
        final ssid = wifi.currentSsid;

        return Row(
          children: [
            Icon(
              isConnected ? Icons.wifi : Icons.wifi_off,
              size: 16,
              color: isConnected ? Colors.blue : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                !isSupported 
                  ? "Wi-Fi (Desktop Mode)" 
                  : (isConnected ? (ssid ?? "Connected") : "Wi-Fi Disconnected"),
                style: TextStyle(
                  fontSize: 12,
                  color: isConnected ? Colors.white : Colors.white60,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isConnected)
              Icon(Icons.check_circle, size: 10, color: Colors.blue.withOpacity(0.5)),
          ],
        );
      },
    );
  }
}
