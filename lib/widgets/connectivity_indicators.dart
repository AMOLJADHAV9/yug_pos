import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/wifi_service.dart';

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
          _buildBluetoothStatus(context),
          const SizedBox(height: 8),
          _buildWifiStatus(context),
        ],
      ),
    );
  }

  Widget _buildBluetoothStatus(BuildContext context) {
    return Consumer<BluetoothPrinterService>(
      builder: (context, bt, _) {
        final isConnected = bt.isConnected;
        final isConnecting = bt.isConnecting;
        
        return Row(
          children: [
            Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              size: 16,
              color: isConnected ? Colors.green : (isConnecting ? Colors.orange : Colors.grey),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isConnecting ? "Connecting..." : (isConnected ? "Printer Connected" : "Printer Disconnected"),
                style: TextStyle(
                  fontSize: 12,
                  color: isConnected ? Colors.white : Colors.white60,
                  fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isConnected)
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
              ),
          ],
        );
      },
    );
  }

  Widget _buildWifiStatus(BuildContext context) {
    return Consumer<WifiService>(
      builder: (context, wifi, _) {
        // Platform check: WifiService is primarily for Android
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
