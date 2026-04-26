import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../models/printer_role.dart';

class LanPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;
  List<PrinterDevice> _devices = [];
  List<PrinterDevice> get devices => _devices;

  // Configuration for KOT
  String? _kotName;
  String? _kotIp;
  int _kotPort = 9100;
  bool _isKotOnline = false;

  // Configuration for Bill
  String? _billName;
  String? _billIp;
  int _billPort = 9100;
  bool _isBillOnline = false;

  PrinterConnectionType _kotConnectionType = PrinterConnectionType.bluetooth;
  PrinterConnectionType _billConnectionType = PrinterConnectionType.bluetooth;

  PrinterConnectionType get kotConnectionType => _kotConnectionType;
  PrinterConnectionType get billConnectionType => _billConnectionType;

  // Getters
  String? get kotName => _kotName;
  String? get kotIp => _kotIp;
  int get kotPort => _kotPort;
  bool get isKotOnline => _isKotOnline;

  String? get billName => _billName;
  String? get billIp => _billIp;
  int get billPort => _billPort;
  bool get isBillOnline => _isBillOnline;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool get arePrintersConfigured => _kotIp != null && _billIp != null;
  bool isRoleConfigured(PrinterRole role) => role == PrinterRole.kot ? _kotIp != null : _billIp != null;

  StreamSubscription? _scanSubscription;
  Timer? _statusTimer;

  LanPrinterService() {
    _init();
    // Periodic status check every 30 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) => checkStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load KOT
    _kotName = prefs.getString('lan_kot_name');
    _kotIp = prefs.getString('lan_kot_ip');
    _kotPort = prefs.getInt('lan_kot_port') ?? 9100;

    // Load Bill
    _billName = prefs.getString('lan_bill_name');
    _billIp = prefs.getString('lan_bill_ip');
    _billPort = prefs.getInt('lan_bill_port') ?? 9100;

    // Load connection types
    final kotTypeStr = prefs.getString('kot_connection_type') ?? 'bluetooth';
    final billTypeStr = prefs.getString('bill_connection_type') ?? 'bluetooth';
    _kotConnectionType = PrinterConnectionType.values.firstWhere((e) => e.toString().split('.').last == kotTypeStr, orElse: () => PrinterConnectionType.bluetooth);
    _billConnectionType = PrinterConnectionType.values.firstWhere((e) => e.toString().split('.').last == billTypeStr, orElse: () => PrinterConnectionType.bluetooth);
    
    checkStatus();
  }

  Future<void> checkStatus() async {
    if (_kotIp != null) {
      _isKotOnline = await testConnection(_kotIp!, _kotPort);
    }
    if (_billIp != null) {
      _isBillOnline = await testConnection(_billIp!, _billPort);
    }
    notifyListeners();
  }

  Future<bool> testConnection(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  void scan() {
    if (_isScanning) return;
    
    _devices.clear();
    _isScanning = true;
    notifyListeners();

    _scanSubscription?.cancel();
    _scanSubscription = _printerManager.discovery(type: PrinterType.network).listen((PrinterDevice event) {
      final index = _devices.indexWhere((p) => p.address == event.address || (p.vendorId == event.vendorId && p.productId == event.productId));
      if (index < 0) {
        _devices.add(event);
      } else {
        _devices[index] = event;
      }
      notifyListeners();
    });

    Future.delayed(const Duration(seconds: 8), () {
      stopScan();
    });
  }

  void stopScan() {
    _isScanning = false;
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<void> saveRolePrinter(String name, String ip, int port, PrinterRole role) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = role == PrinterRole.kot ? 'lan_kot' : 'lan_bill';

    await prefs.setString('${prefix}_name', name);
    await prefs.setString('${prefix}_ip', ip);
    await prefs.setInt('${prefix}_port', port);

    if (role == PrinterRole.kot) {
      _kotName = name;
      _kotIp = ip;
      _kotPort = port;
      _isKotOnline = await testConnection(ip, port);
    } else {
      _billName = name;
      _billIp = ip;
      _billPort = port;
      _isBillOnline = await testConnection(ip, port);
    }
    
    // Set this service as the handler for this role
    await prefs.setString(role == PrinterRole.kot ? 'kot_connection_type' : 'bill_connection_type', 'lan');
    if (role == PrinterRole.kot) _kotConnectionType = PrinterConnectionType.lan;
    else _billConnectionType = PrinterConnectionType.lan;

    notifyListeners();
  }

  Future<bool> testPrintRole(PrinterRole role) async {
    final ip = role == PrinterRole.kot ? _kotIp : _billIp;
    final port = role == PrinterRole.kot ? _kotPort : _billPort;
    if (ip == null) return false;

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes += generator.text("YUG POS", styles: PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.text("LAN ${role.toString().split('.').last.toUpperCase()} TEST PRINT", styles: PosStyles(align: PosAlign.center));
    bytes += generator.text("IP: $ip Port: $port", styles: PosStyles(align: PosAlign.center));
    bytes += generator.feed(2);
    bytes += generator.cut();

    return await printRawBytes(bytes, role: role);
  }

  Future<bool> printRawBytes(List<int> bytes, {PrinterRole role = PrinterRole.bill, bool isRetry = false}) async {
    final ip = role == PrinterRole.kot ? _kotIp : _billIp;
    final port = role == PrinterRole.kot ? _kotPort : _billPort;
    final name = role == PrinterRole.kot ? _kotName : _billName;

    if (ip == null) {
      return false;
    }

    try {
      final success = await _printerManager.connect(
        type: PrinterType.network,
        model: TcpPrinterInput(ipAddress: ip, port: port),
      );

      if (success) {
        await _printerManager.send(type: PrinterType.network, bytes: bytes);
        await _printerManager.disconnect(type: PrinterType.network);
        return true;
      } else {
        if (!isRetry) {
          await Future.delayed(const Duration(milliseconds: 500));
          return await printRawBytes(bytes, role: role, isRetry: true);
        }
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}
