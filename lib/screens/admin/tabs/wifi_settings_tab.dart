import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wifi_iot/wifi_iot.dart';
import '../../../services/wifi_service.dart';
import '../../../utils/navigator_utils.dart';

class WifiSettingsTab extends StatefulWidget {
  const WifiSettingsTab({super.key});

  @override
  State<WifiSettingsTab> createState() => _WifiSettingsTabState();
}

class _WifiSettingsTabState extends State<WifiSettingsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WifiService>().scanNetworks();
    });
  }

  void _showConnectDialog(WifiNetwork network) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141615),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        title: Text("Connect to ${network.ssid}", 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter Password",
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.lock, color: Color(0xFFFCDD22)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordController.text;
              safePop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Connecting to ${network.ssid}...")),
              );

              final success = await context.read<WifiService>().connect(network.ssid!, password);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? "Connected successfully!" : "Failed to connect."),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFCDD22),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("CONNECT"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "WiFi Settings",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCDD22).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.wifi, size: 64, color: Color(0xFFFCDD22)),
                    ),
                    const SizedBox(height: 24),
                    const Text("Wi-Fi Managed by System", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 64),
                      child: Text(
                        "On Desktop, network connections are managed directly by your operating system's built-in network menu.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (Platform.isWindows) {
                          Process.run('cmd', ['/c', 'start', 'ms-settings:network-wifi']);
                        } else if (Platform.isMacOS) {
                          Process.run('open', ['/System/Library/PreferencePanes/Network.prefPane']);
                        }
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text("Open OS Settings", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFCDD22),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Consumer<WifiService>(
      builder: (context, wifi, child) {
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
                        "WiFi Settings",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        wifi.isConnected && wifi.currentSsid != null
                            ? "Connected to: ${wifi.currentSsid}"
                            : "Not connected to any network",
                        style: TextStyle(color: wifi.isConnected ? const Color(0xFFFCDD22) : Colors.white54),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (wifi.isConnected)
                        TextButton.icon(
                          onPressed: () => wifi.disconnect(),
                          icon: const Icon(Icons.link_off, color: Colors.redAccent),
                          label: const Text("Disconnect", style: TextStyle(color: Colors.redAccent)),
                        ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        onPressed: wifi.isScanning ? null : () => wifi.scanNetworks(),
                        icon: wifi.isScanning 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.refresh),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFCDD22),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Expanded(
                child: wifi.networks.isEmpty && !wifi.isScanning
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off, size: 64, color: Colors.white.withOpacity(0.1)),
                            const SizedBox(height: 16),
                            const Text("No networks found", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                "Please ensure WiFi and Location (GPS) are turned ON in your device settings.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () => wifi.scanNetworks(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text("Try Again", style: TextStyle(color: Color(0xFFFCDD22))),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: wifi.networks.length,
                        separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05)),
                        itemBuilder: (context, index) {
                          final network = wifi.networks[index];
                          final isCurrent = wifi.currentSsid == network.ssid;
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isCurrent ? const Color(0xFFFCDD22).withOpacity(0.1) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.wifi, 
                                color: isCurrent ? const Color(0xFFFCDD22) : Colors.white70,
                                size: 24,
                              ),
                            ),
                            title: Text(
                              network.ssid ?? "Unknown Network",
                              style: TextStyle(
                                color: Colors.white, 
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal
                              ),
                            ),
                            subtitle: Text(
                              "Signal: ${network.level ?? 'NA'} dBm",
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                            ),
                            trailing: isCurrent 
                              ? const Icon(Icons.check_circle, color: Color(0xFFFCDD22))
                              : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white24),
                            onTap: isCurrent ? null : () => _showConnectDialog(network),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
