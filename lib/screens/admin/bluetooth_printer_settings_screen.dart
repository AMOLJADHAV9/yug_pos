import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../models/printer_role.dart';

class BluetoothPrinterSettingsScreen extends StatefulWidget {
  const BluetoothPrinterSettingsScreen({super.key});

  @override
  State<BluetoothPrinterSettingsScreen> createState() => _BluetoothPrinterSettingsScreenState();
}

class _BluetoothPrinterSettingsScreenState extends State<BluetoothPrinterSettingsScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  bool _showSavedSuccess = false;

  // Modern Color Palette
  final Color bgColor = const Color(0xFF0F1512);
  final Color cardColor = const Color(0xFF131A12);
  final Color themeColor = const Color(0xFFF0C030); // Vibrant Gold/Yellow
  final Color borderColor = const Color(0xFF2A3028);
  final Color successColor = const Color(0xFF22C55E);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    
    // Initial scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothPrinterService>().scan();
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
    final printerService = context.watch<BluetoothPrinterService>();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(printerService),
            _buildStatusBadge(printerService),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildOverviewStep(printerService),
                  _buildSelectionStep(printerService, PrinterRole.kot),
                  _buildSelectionStep(printerService, PrinterRole.bill),
                ],
              ),
            ),
            _buildPageIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BluetoothPrinterService printerService) {
    String title = "PRINTER SETTINGS";
    if (_currentPage == 1) title = "SELECT KOT PRINTER";
    if (_currentPage == 2) title = "SELECT BILL PRINTER";

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
          if (_currentPage != 0)
            IconButton(
              onPressed: () => printerService.scan(),
              icon: printerService.isScanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: themeColor),
                    )
                  : Icon(Icons.refresh, color: Colors.grey[600], size: 20),
            )
          else
            IconButton(
              onPressed: () => printerService.scan(),
              icon: Icon(Icons.refresh, color: Colors.grey[600], size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BluetoothPrinterService printerService) {
    final isAnyConnected = printerService.isConnected;
    final deviceName = printerService.lastConnectedName ?? "DISCONNECTED";

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1F0F),
            border: Border.all(color: const Color(0xFF1E4A1E)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isAnyConnected ? successColor : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${isAnyConnected ? 'CONNECTED' : 'STATUS'}: $deviceName",
                style: GoogleFonts.spaceGrotesk(
                  color: isAnyConnected ? successColor : Colors.grey[400],
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewStep(BluetoothPrinterService printerService) {
    final kotSelected = printerService.kotAddress != null;
    final billSelected = printerService.billAddress != null;
    final allSelected = kotSelected && billSelected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel("KOT PRINTER"),
          _buildPrinterSlot(
            title: kotSelected ? printerService.kotName! : "Not Selected",
            subtitle: kotSelected ? printerService.kotAddress! : "Tap to select KOT printer",
            isSelected: kotSelected,
            onTap: () => _goTo(1),
          ),
          const SizedBox(height: 16),
          _buildSectionLabel("BILL PRINTER"),
          _buildPrinterSlot(
            title: billSelected ? printerService.billName! : "Not Selected",
            subtitle: billSelected ? printerService.billAddress! : "Tap to select Bill printer",
            isSelected: billSelected,
            onTap: () => _goTo(2),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: allSelected && !_showSavedSuccess
                  ? () {
                      setState(() => _showSavedSuccess = true);
                    }
                  : (_showSavedSuccess ? () => Navigator.pop(context) : null),
              icon: Icon(_showSavedSuccess ? Icons.check_circle : Icons.save, size: 16),
              label: Text(
                _showSavedSuccess ? "SETTINGS SAVED" : "SAVE SETTINGS",
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _showSavedSuccess ? successColor : themeColor,
                foregroundColor: _showSavedSuccess ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                disabledBackgroundColor: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_showSavedSuccess)
            _buildNotice(
              "Please select both KOT and Bill printer to continue",
              enabled: !allSelected,
            )
          else
            _buildSuccessBanner(),
        ],
      ),
    );
  }

  Widget _buildSelectionStep(BluetoothPrinterService service, PrinterRole role) {
    final devices = service.devices;
    final roleAddress = role == PrinterRole.kot ? service.kotAddress : service.billAddress;

    return Column(
      children: [
        Expanded(
          child: devices.isEmpty && !service.isScanning
              ? _buildEmptyState(service)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isSelected = roleAddress == device.address;
                    return _buildDeviceItem(device, isSelected, role, service);
                  },
                ),
        ),
        _buildPrintTestButton(service, role),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          color: Colors.grey[500],
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: themeColor, width: 1.5)
              : Border.all(color: const Color(0xFF3A3A2A), style: BorderStyle.none),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: isSelected
                ? null
                : BoxDecoration(
                    border: Border.all(color: const Color(0xFF3A3A2A), width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A1A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.print, color: isSelected ? themeColor : Colors.grey[700], size: 18),
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
                Icon(Icons.chevron_right, color: Colors.grey[800], size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotice(String text, {bool enabled = true}) {
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
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: successColor.withOpacity(0.2)),
            child: Icon(Icons.check, size: 14, color: successColor),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Settings Saved Successfully!",
                style: GoogleFonts.spaceGrotesk(color: successColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              Text(
                "You can now print KOT and Bill.",
                style: GoogleFonts.spaceGrotesk(color: successColor.withOpacity(0.7), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(PrinterDevice device, bool isSelected, PrinterRole role, BluetoothPrinterService service) {
    return GestureDetector(
      onTap: () {
        service.saveRolePrinter(device, role);
        Future.delayed(const Duration(milliseconds: 300), () => _goTo(0));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A200F) : cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? themeColor : borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.print, color: isSelected ? themeColor : Colors.grey[700], size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name ?? "Unknown Device",
                    style: GoogleFonts.spaceGrotesk(
                      color: isSelected ? Colors.white : Colors.grey[400],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    device.address ?? "No Address",
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

  Widget _buildPrintTestButton(BluetoothPrinterService service, PrinterRole role) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => service.testPrintRole(role),
          icon: Icon(Icons.print, size: 16, color: themeColor),
          label: Text(
            "PRINT TEST PAGE",
            style: GoogleFonts.spaceGrotesk(color: themeColor, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: BorderSide(color: themeColor, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BluetoothPrinterService service) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 48, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text(
            "Searching for printers...",
            style: GoogleFonts.spaceGrotesk(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => service.scan(),
            child: Text("RETRY SCAN", style: GoogleFonts.spaceGrotesk(color: themeColor)),
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
        children: List.generate(3, (index) {
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
