import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../services/lan_printer_service.dart';
import '../../services/wifi_service.dart';
import '../../models/printer_role.dart';

class LanPrinterSettingsScreen extends StatefulWidget {
  const LanPrinterSettingsScreen({super.key});

  @override
  State<LanPrinterSettingsScreen> createState() => _LanPrinterSettingsScreenState();
}

class _LanPrinterSettingsScreenState extends State<LanPrinterSettingsScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: "9100");

  // Premium Dark Palette
  final Color bgColor = const Color(0xFF0F1218);
  final Color cardColor = const Color(0xFF0F1420);
  final Color themeColor = const Color(0xFFA78BFA); // Soft Lavender/Purple
  final Color borderColor = const Color(0xFF1E2A38);
  final Color successColor = const Color(0xFF22C55E);
  final Color warnColor = const Color(0xFFE0A030);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    
    // Initial scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LanPrinterService>().scan();
      context.read<WifiService>().refreshStatus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
    setState(() {
      _currentPage = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lanService = context.watch<LanPrinterService>();
    final wifiService = context.watch<WifiService>();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildNetworkBadge(wifiService),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildOverviewStep(lanService, wifiService),
                  _buildSelectionStep(lanService, PrinterRole.kot),
                  _buildSelectionStep(lanService, PrinterRole.bill),
                  _buildSuccessStep(lanService),
                ],
              ),
            ),
            _buildPageIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    String title = "LAN PRINTER SETTINGS";
    if (_currentPage == 1) title = "SELECT KOT LAN PRINTER";
    if (_currentPage == 2) title = "SELECT BILL LAN PRINTER";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111A28),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (_currentPage == 0) {
                Navigator.pop(context);
              } else {
                _goTo(0);
              }
            },
            icon: Icon(Icons.arrow_back, color: Colors.grey[600], size: 22),
          ),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                color: themeColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          IconButton(
            onPressed: () => context.read<LanPrinterService>().scan(),
            icon: Icon(Icons.refresh, color: Colors.grey[600], size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkBadge(WifiService wifi) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 10, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1A10),
            border: Border.all(color: const Color(0xFF1A4A2A)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPulseDot(),
              const SizedBox(width: 8),
              Text(
                "NETWORK: ${wifi.currentSsid ?? 'CONNECTED'}",
                style: GoogleFonts.spaceGrotesk(
                  color: successColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulseDot() {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: successColor,
        boxShadow: [
          BoxShadow(color: successColor.withOpacity(0.5), blurRadius: 4, spreadRadius: 1),
        ],
      ),
    );
  }

  Widget _buildOverviewStep(LanPrinterService lan, WifiService wifi) {
    bool isKotSet = lan.kotIp != null;
    bool isBillSet = lan.billIp != null;
    bool allSet = isKotSet && isBillSet;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWarningBanner("Printer and device must be on the same Wi-Fi / LAN network"),
          const SizedBox(height: 16),
          _buildSectionLabel("KOT PRINTER (LAN)"),
          _buildPrinterSlot(
            title: isKotSet ? lan.kotName ?? "KOT Printer" : "Not Selected",
            subtitle: isKotSet ? "${lan.kotIp}:${lan.kotPort}" : "Tap to select KOT LAN printer",
            isSelected: isKotSet,
            isOnline: lan.isKotOnline,
            onTap: () => _goTo(1),
          ),
          const SizedBox(height: 16),
          _buildSectionLabel("BILL PRINTER (LAN)"),
          _buildPrinterSlot(
            title: isBillSet ? lan.billName ?? "Bill Printer" : "Not Selected",
            subtitle: isBillSet ? "${lan.billIp}:${lan.billPort}" : "Tap to select Bill LAN printer",
            isSelected: isBillSet,
            isOnline: lan.isBillOnline,
            onTap: () => _goTo(2),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: allSet ? () => _goTo(3) : null,
              icon: const Icon(Icons.save, size: 16),
              label: Text("SAVE SETTINGS", style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                disabledBackgroundColor: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildNotice("Select both KOT and Bill LAN printer to continue", enabled: !allSet),
        ],
      ),
    );
  }

  Widget _buildSelectionStep(LanPrinterService lan, PrinterRole role) {
    final devices = lan.devices;
    
    return Column(
      children: [
        _buildScanSummary(devices.length),
        Expanded(
          child: devices.isEmpty && !lan.isScanning
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final d = devices[index];
                    return _buildDeviceItem(d, lan, role);
                  },
                ),
        ),
        _buildManualInputSection(lan, role),
        _buildTestPrintButton(lan, role),
      ],
    );
  }

  Widget _buildScanSummary(int count) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Text("Auto-discovered on network:", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
          const Spacer(),
          Text("$count found", style: TextStyle(color: themeColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(PrinterDevice device, LanPrinterService lan, PrinterRole role) {
    final isSelected = role == PrinterRole.kot 
        ? (lan.kotIp == device.address)
        : (lan.billIp == device.address);

    return GestureDetector(
      onTap: () {
        lan.saveRolePrinter(device.name ?? "Network Printer", device.address ?? "", 9100, role);
        Future.delayed(const Duration(milliseconds: 300), () => _goTo(0));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF150F28) : cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? themeColor : borderColor),
        ),
        child: Row(
          children: [
            Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name ?? "Unknown Printer", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  Text("${device.address} · Online", style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                ],
              ),
            ),
            if (isSelected) 
               Icon(Icons.check_circle, color: successColor, size: 20)
            else
               Icon(Icons.chevron_right, color: Colors.grey[800], size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildManualInputSection(LanPrinterService lan, PrinterRole role) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ADD MANUALLY BY IP", style: GoogleFonts.spaceGrotesk(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: "192.168.1.xxx",
                    hintStyle: TextStyle(color: Colors.grey[800]),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: borderColor)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _portController,
                  style: TextStyle(color: themeColor, fontSize: 12),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.all(8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: borderColor)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final ip = _ipController.text.trim();
                  final port = int.tryParse(_portController.text.trim()) ?? 9100;
                  if (ip.isNotEmpty) {
                    lan.saveRolePrinter("Manual Printer", ip, port, role);
                    _ipController.clear();
                    _goTo(0);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                ),
                child: const Text("ADD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTestPrintButton(LanPrinterService lan, PrinterRole role) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OutlinedButton.icon(
        onPressed: () => lan.testPrintRole(role),
        icon: Icon(Icons.print, size: 14, color: themeColor),
        label: Text("PING TEST", style: GoogleFonts.spaceGrotesk(color: themeColor, fontSize: 11, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: themeColor, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSuccessStep(LanPrinterService lan) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel("KOT PRINTER (LAN)"),
          _buildPrinterSlot(title: lan.kotName ?? "KOT Printer", subtitle: "${lan.kotIp}:${lan.kotPort}", isSelected: true, isOnline: lan.isKotOnline, onTap: () {}),
          const SizedBox(height: 16),
          _buildSectionLabel("BILL PRINTER (LAN)"),
          _buildPrinterSlot(title: lan.billName ?? "Bill Printer", subtitle: "${lan.billIp}:${lan.billPort}", isSelected: true, isOnline: lan.isBillOnline, onTap: () {}),
          const SizedBox(height: 24),
          _buildSuccessBanner(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text("DONE", style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1200), border: Border.all(color: const Color(0xFF5A3A00)), borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: warnColor),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: warnColor, fontSize: 11, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
    );
  }

  Widget _buildPrinterSlot({required String title, required String subtitle, required bool isSelected, required bool isOnline, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: themeColor, width: 1.5) : Border.all(color: borderColor, style: BorderStyle.none),
        ),
        child: Row(
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: isOnline ? successColor : Colors.grey)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.spaceGrotesk(color: isSelected ? Colors.white : Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: GoogleFonts.spaceGrotesk(color: Colors.grey[600], fontSize: 10)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: isSelected ? themeColor : Colors.grey[800], size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF0C2210), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF166534))),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 24, color: successColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Settings Saved Successfully!", style: GoogleFonts.spaceGrotesk(color: successColor, fontSize: 12, fontWeight: FontWeight.w700)),
                Text("You can now print KOT and Bill via LAN.", style: GoogleFonts.spaceGrotesk(color: successColor.withOpacity(0.7), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(String text, {required bool enabled}) {
    if (!enabled) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF12141E), borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.spaceGrotesk(color: Colors.grey[600], fontSize: 11, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lan_outlined, size: 48, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text("No LAN printers detected", style: GoogleFonts.spaceGrotesk(color: Colors.grey[600], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          final active = _currentPage == index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? themeColor : borderColor,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
