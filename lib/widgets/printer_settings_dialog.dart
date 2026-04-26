import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/report_service.dart';
import '../utils/navigator_utils.dart';
import '../models/printer_role.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

class PrinterSettingsDialog extends StatefulWidget {
  const PrinterSettingsDialog({super.key});

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  int _view = 0; // 0: Dashboard, 1: KOT Selection, 2: Bill Selection
  PrinterDevice? _tempKot;
  PrinterDevice? _tempBill;
  bool _showSuccessBanner = false;

  @override
  void initState() {
    super.initState();
    final bt = context.read<BluetoothPrinterService>();
    if (bt.kotAddress != null) {
      _tempKot = PrinterDevice(name: bt.kotName ?? 'KOT Printer', address: bt.kotAddress!);
    }
    if (bt.billAddress != null) {
      _tempBill = PrinterDevice(name: bt.billName ?? 'Bill Printer', address: bt.billAddress!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0E1111),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        height: 650,
        child: Column(
          children: [
            _buildHeader(),
            _buildStatusBar(),
            Expanded(child: _buildContent()),
            _buildBottomBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String title = "PRINTER SETTINGS";
    if (_view == 1) title = "SELECT KOT PRINTER";
    if (_view == 2) title = "SELECT BILL PRINTER";

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (_view != 0)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFFFCDD22)),
              onPressed: () => setState(() => _view = 0),
            )
          else
            const Icon(Icons.print, color: Color(0xFFFCDD22)),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (_view == 0)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
              onPressed: () => context.read<BluetoothPrinterService>().scan(),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Consumer<BluetoothPrinterService>(
      builder: (context, bt, _) {
        final hasKOT = bt.kotAddress != null;
        final hasBill = bt.billAddress != null;
        final isConfigured = hasKOT && hasBill;
        
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isConfigured ? const Color(0xFF0A2D23).withOpacity(0.8) : const Color(0xFF2D240A).withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (isConfigured ? const Color(0xFF1BAD8C) : Colors.orange).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(isConfigured ? Icons.check_circle : Icons.info_outline, color: isConfigured ? const Color(0xFF1BAD8C) : Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isConfigured 
                      ? "SYSTEM READY: KOT & BILL CONFIGURED" 
                      : (hasKOT || hasBill ? "PARTIAL SETUP: ${hasKOT ? 'KOT' : 'BILL'} SAVED" : "SETUP REQUIRED: SELECT PRINTERS"),
                  style: TextStyle(color: isConfigured ? const Color(0xFF1BAD8C) : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    if (_view == 0) return _buildDashboard();
    return _buildDeviceSelection();
  }

  Widget _buildDashboard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildSelectionCard(
            role: PrinterRole.kot,
            device: _tempKot,
            onTap: () {
              setState(() => _view = 1);
              context.read<BluetoothPrinterService>().scan();
            },
          ),
          const SizedBox(height: 16),
          _buildSelectionCard(
            role: PrinterRole.bill,
            device: _tempBill,
            onTap: () {
              setState(() => _view = 2);
              context.read<BluetoothPrinterService>().scan();
            },
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: (_tempKot != null && _tempBill != null) ? _saveSettings : null,
              icon: const Icon(Icons.save, size: 20),
              label: const Text("SAVE SETTINGS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFCDD22),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: Colors.white10,
                disabledForegroundColor: Colors.white30,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSelectionCard({required PrinterRole role, PrinterDevice? device, required VoidCallback onTap}) {
    final String title = role == PrinterRole.kot ? "KOT PRINTER" : "BILL PRINTER";
    final bool isSelected = device != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D1D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: Icon(role == PrinterRole.kot ? Icons.restaurant : Icons.receipt_long, color: Colors.white70, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    isSelected ? device!.name ?? "Unknown Device" : "Not Selected",
                    style: TextStyle(color: isSelected ? Colors.white : Colors.white30, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (isSelected)
                    Text(device!.address ?? "", style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white12),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSelection() {
    return Consumer<BluetoothPrinterService>(
      builder: (context, bt, _) {
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: bt.devices.length,
                itemBuilder: (context, i) {
                  final d = bt.devices[i];
                  final isCurrentlySelected = (_view == 1 ? _tempKot?.address : _tempBill?.address) == d.address;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D1D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isCurrentlySelected ? const Color(0xFFFCDD22) : Colors.transparent),
                    ),
                    child: ListTile(
                      onTap: () => setState(() {
                        if (_view == 1) _tempKot = d;
                        else _tempBill = d;
                        _view = 0;
                      }),
                      leading: Icon(Icons.print, color: Colors.white54, size: 20),
                      title: Text(d.name ?? "Unknown", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text(d.address ?? "", style: const TextStyle(color: Colors.white24, fontSize: 10)),
                      trailing: isCurrentlySelected ? const Icon(Icons.check_circle, color: Color(0xFFFCDD22)) : const Icon(Icons.chevron_right, color: Colors.white10),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final role = _view == 1 ? PrinterRole.kot : PrinterRole.bill;
                    final dev = _view == 1 ? _tempKot : _tempBill;
                    if (dev != null) {
                      bt.saveRolePrinter(dev, role);
                      bt.testPrintRole(role);
                    }
                  },
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text("PRINT TEST PAGE", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFCDD22),
                    side: const BorderSide(color: Color(0xFFFCDD22)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBanner() {
    bool hasBoth = _tempKot != null && _tempBill != null;
    
    if (_showSuccessBanner) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Color(0xFF102818), borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.black, size: 14),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Settings Saved Successfully!", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text("You can now print KOT and Bill.", style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Color(0xFF1C1C1C), borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasBoth ? "Tap SAVE SETTINGS to apply." : "Please select both KOT and Bill printer to continue.",
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    final bt = context.read<BluetoothPrinterService>();
    if (_tempKot != null) await bt.saveRolePrinter(_tempKot!, PrinterRole.kot);
    if (_tempBill != null) await bt.saveRolePrinter(_tempBill!, PrinterRole.bill);
    
    setState(() => _showSuccessBanner = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) safePop(context);
    });
  }
}

