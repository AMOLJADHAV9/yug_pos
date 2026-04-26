import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../services/usb_printer_service.dart';
import '../../models/printer_role.dart';

class UsbPrinterSettingsScreen extends StatefulWidget {
  const UsbPrinterSettingsScreen({super.key});

  @override
  State<UsbPrinterSettingsScreen> createState() => _UsbPrinterSettingsScreenState();
}

class _UsbPrinterSettingsScreenState extends State<UsbPrinterSettingsScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  bool _showSavedSuccess = false;

  // Modern Color Palette (Matching the requested HTML design)
  final Color bgColor = const Color(0xFF0F1512);
  final Color cardColor = const Color(0xFF131A12);
  final Color themeColor = const Color(0xFFF0C030); // Vibrant Gold/Yellow
  final Color borderColor = const Color(0xFF2A3028);
  final Color usbColor = const Color(0xFF3B9EFF); // Blue for USB
  final Color successColor = const Color(0xFF22C55E);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    
    // Initial scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UsbPrinterService>().scan();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (_showSavedSuccess) {
      setState(() => _showSavedSuccess = false);
    }
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
    final printerService = context.watch<UsbPrinterService>();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(printerService),
            _buildUsbStatusBadge(printerService),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildOverviewStep(printerService),
                  _buildSelectionStep(printerService, PrinterRole.kot),
                  _buildSelectionStep(printerService, PrinterRole.bill),
                  _buildSuccessStep(printerService),
                ],
              ),
            ),
            _buildPageIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(UsbPrinterService printerService) {
    String title = "USB PRINTER SETTINGS";
    if (_currentPage == 1) title = "SELECT KOT USB PRINTER";
    if (_currentPage == 2) title = "SELECT BILL USB PRINTER";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2218),
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
            icon: Icon(Icons.arrow_back, color: Colors.grey[500], size: 22),
          ),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                color: themeColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          IconButton(
            onPressed: () => printerService.scan(),
            icon: printerService.isScanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: usbColor),
                  )
                : Icon(Icons.refresh, color: Colors.grey[600], size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildUsbStatusBadge(UsbPrinterService printerService) {
    final hasDevices = printerService.devices.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1A2A),
            border: Border.all(color: const Color(0xFF1E3A5F)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasDevices ? usbColor : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasDevices ? "USB HOST MODE: ACTIVE" : "USB: NO DEVICES FOUND",
                style: GoogleFonts.spaceGrotesk(
                  color: hasDevices ? usbColor : Colors.red,
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

  Widget _buildOverviewStep(UsbPrinterService printerService) {
    final kotSelected = printerService.kotName != null;
    final billSelected = printerService.billName != null;
    final allSelected = kotSelected && billSelected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!kIsWeb && Platform.isAndroid)
            _buildWarningBanner("Connect printer via USB-OTG cable before selecting"),
          const SizedBox(height: 16),
          _buildSectionLabel("KOT PRINTER (USB)"),
          _buildPrinterSlot(
            title: kotSelected ? printerService.kotName! : "Not Selected",
            subtitle: kotSelected ? printerService.kotAddress ?? "Configured" : "Tap to select KOT USB printer",
            isSelected: kotSelected,
            onTap: () => _goTo(1),
          ),
          const SizedBox(height: 16),
          _buildSectionLabel("BILL PRINTER (USB)"),
          _buildPrinterSlot(
            title: billSelected ? printerService.billName! : "Not Selected",
            subtitle: billSelected ? printerService.billAddress ?? "Configured" : "Tap to select Bill USB printer",
            isSelected: billSelected,
            onTap: () => _goTo(2),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: allSelected ? () => _goTo(3) : null,
              icon: const Icon(Icons.save, size: 16),
              label: Text(
                "SAVE SETTINGS",
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
              ),
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
          _buildNotice(
            "Select both KOT and Bill USB printer to continue",
            enabled: !allSelected,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionStep(UsbPrinterService service, PrinterRole role) {
    final devices = service.devices;
    final savedAddress = role == PrinterRole.kot ? service.kotAddress : service.billAddress;
    final savedName = role == PrinterRole.kot ? service.kotName : service.billName;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text("Detected USB devices:", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF0F1A2A), border: Border.all(color: const Color(0xFF1E3A5F)), borderRadius: BorderRadius.circular(6)),
                child: Text("${devices.length} found", style: TextStyle(color: usbColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: devices.isEmpty && !service.isScanning
              ? _buildEmptyState(service)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isSelected = savedAddress == device.address || savedName == device.name;
                    return _buildDeviceItem(device, isSelected, role, service);
                  },
                ),
        ),
        _buildPrintTestButton(service, role),
      ],
    );
  }

  Widget _buildSuccessStep(UsbPrinterService printerService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel("KOT PRINTER (USB)"),
          _buildPrinterSlot(
            title: printerService.kotName ?? "Unknown",
            subtitle: "VendorID: ${printerService.kotAddress ?? 'Targeted'}",
            isSelected: true,
            activeColor: usbColor,
            onTap: () => _goTo(1),
          ),
          const SizedBox(height: 16),
          _buildSectionLabel("BILL PRINTER (USB)"),
          _buildPrinterSlot(
            title: printerService.billName ?? "Unknown",
            subtitle: "VendorID: ${printerService.billAddress ?? 'Targeted'}",
            isSelected: true,
            activeColor: Colors.white54,
            onTap: () => _goTo(2),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check_circle, size: 16),
              label: Text(
                "DONE",
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSuccessBanner(),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1200),
        border: Border.all(color: const Color(0xFF7C4A00)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF0A030)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFF0A030), fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          color: Colors.grey[600],
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildPrinterSlot({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final finalActiveColor = activeColor ?? themeColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: finalActiveColor, width: 1.5)
              : Border.all(color: const Color(0xFF3A3A2A), style: BorderStyle.none),
        ),
        child: Container(
          decoration: isSelected
              ? null
              : BoxDecoration(
                  border: Border.all(color: const Color(0xFF3A3A2A), width: 1.5, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(12),
                ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.print, color: isSelected ? finalActiveColor : Colors.grey[700], size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.spaceGrotesk(
                        color: isSelected ? Colors.white : Colors.grey[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.grey[600],
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: isSelected ? finalActiveColor : Colors.grey[800], size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C2210),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF166534)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check, size: 20, color: Color(0xFF22C55E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Settings Saved Successfully!",
                  style: GoogleFonts.spaceGrotesk(color: successColor, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text(
                  "You can now print KOT and Bill via USB.",
                  style: GoogleFonts.spaceGrotesk(color: successColor.withOpacity(0.7), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(PrinterDevice device, bool isSelected, PrinterRole role, UsbPrinterService service) {
    return GestureDetector(
      onTap: () async {
        await service.saveRolePrinter(device, role);
        Future.delayed(const Duration(milliseconds: 300), () => _goTo(0));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F1A20) : cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? usbColor : borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0F1A2A) : const Color(0xFF1A2A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.usb, color: isSelected ? usbColor : Colors.grey[700], size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name ?? "USB Printer",
                    style: GoogleFonts.spaceGrotesk(
                      color: isSelected ? Colors.white : Colors.grey[400],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    "VID: ${device.vendorId} · PID: ${device.productId}",
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.grey[700],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(shape: BoxShape.circle, color: successColor),
                child: const Icon(Icons.check, color: Colors.white, size: 12),
              )
            else
              Icon(Icons.chevron_right, color: Colors.grey[800], size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPrintTestButton(UsbPrinterService service, PrinterRole role) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => service.testPrintRole(role),
          icon: Icon(Icons.print, size: 16, color: usbColor),
          label: Text(
            "PRINT TEST PAGE",
            style: GoogleFonts.spaceGrotesk(color: usbColor, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: BorderSide(color: usbColor, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildNotice(String text, {required bool enabled}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A2A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.grey[600],
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(UsbPrinterService service) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.usb, size: 48, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text(
            service.isScanning ? "Scanning for USB devices..." : "No USB printers detected",
            style: GoogleFonts.spaceGrotesk(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => service.scan(),
            child: Text("RETRY SCAN", style: GoogleFonts.spaceGrotesk(color: usbColor)),
          ),
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
              color: active ? usbColor : borderColor,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
