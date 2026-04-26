import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../models/printer_role.dart';

class UsbPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;
  List<PrinterDevice> _devices = [];
  List<PrinterDevice> get devices => _devices;

  // Active role-based devices
  PrinterDevice? _kotDevice;
  PrinterDevice? _billDevice;
  PrinterDevice? get kotDevice => _kotDevice;
  PrinterDevice? get billDevice => _billDevice;

  // KOT Config
  String? _kotName;
  String? _kotVendorId;
  String? _kotProductId;
  String? _kotAddress;

  // Bill Config
  String? _billName;
  String? _billVendorId;
  String? _billProductId;
  String? _billAddress;

  PrinterConnectionType _kotConnectionType = PrinterConnectionType.bluetooth;
  PrinterConnectionType _billConnectionType = PrinterConnectionType.bluetooth;

  PrinterConnectionType get kotConnectionType => _kotConnectionType;
  PrinterConnectionType get billConnectionType => _billConnectionType;

  // Getters for configuration
  String? get kotName => _kotName;
  String? get kotAddress => _kotAddress;
  String? get billName => _billName;
  String? get billAddress => _billAddress;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  PrinterRole? _lastConnectedRole;

  bool get arePrintersConfigured => _kotName != null && _billName != null;
  bool isRoleConfigured(PrinterRole role) => role == PrinterRole.kot ? _kotName != null : _billName != null;
  
  // Compatibility with existing order/dashboard guards
  bool get hasSavedPrinter => _kotName != null || _billName != null;

  StreamSubscription? _scanSubscription;
  Timer? _heartbeatTimer;

  UsbPrinterService() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isLinux)) {
      _init();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) => scan(silent: true));
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load KOT
    _kotName = prefs.getString('usb_kot_name');
    _kotAddress = prefs.getString('usb_kot_address');
    _kotVendorId = prefs.getString('usb_kot_vendor_id');
    _kotProductId = prefs.getString('usb_kot_product_id');

    // Load Bill
    _billName = prefs.getString('usb_bill_name');
    _billAddress = prefs.getString('usb_bill_address');
    _billVendorId = prefs.getString('usb_bill_vendor_id');
    _billProductId = prefs.getString('usb_bill_product_id');
    
    // Load connection types
    final kotTypeStr = prefs.getString('kot_connection_type') ?? 'bluetooth';
    final billTypeStr = prefs.getString('bill_connection_type') ?? 'bluetooth';
    _kotConnectionType = PrinterConnectionType.values.firstWhere((e) => e.toString().split('.').last == kotTypeStr, orElse: () => PrinterConnectionType.bluetooth);
    _billConnectionType = PrinterConnectionType.values.firstWhere((e) => e.toString().split('.').last == billTypeStr, orElse: () => PrinterConnectionType.bluetooth);
    
    _isConnected = false;
    _lastConnectedRole = null;

    if (_kotName != null || _billName != null) {
      scan(silent: true); 
    }
  }

  void scan({bool silent = false}) {
    if (_isScanning) return;
    
    if (!silent) {
      _devices.clear();
      _isScanning = true;
      notifyListeners();
    }

    _scanSubscription?.cancel();
    _scanSubscription = _printerManager.discovery(type: PrinterType.usb, isBle: false).listen((PrinterDevice event) async {
      final index = _devices.indexWhere((p) => p.address == event.address || p.name == event.name);
      if (index < 0) {
        _devices.add(event);
      } else {
        _devices[index] = event;
      }
      
      // Auto-reconnect/Resolve objects
      _resolveDevicesFromConfig(event);
      
      notifyListeners();
    });

    if (!silent) {
      Future.delayed(const Duration(seconds: 10), () {
        stopScan();
      });
    }
  }

  void _resolveDevicesFromConfig(PrinterDevice event) {
    // Resolve KOT
    if (_kotDevice == null && _kotName != null) {
      if (event.name == _kotName || event.address == _kotAddress || 
          (event.vendorId == _kotVendorId && event.productId == _kotProductId)) {
           _kotDevice = event;
      }
    }
    // Resolve Bill
    if (_billDevice == null && _billName != null) {
      if (event.name == _billName || event.address == _billAddress || 
          (event.vendorId == _billVendorId && event.productId == _billProductId)) {
           _billDevice = event;
      }
    }
  }

  void stopScan() {
    _isScanning = false;
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<void> saveRolePrinter(PrinterDevice device, PrinterRole role) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = role == PrinterRole.kot ? 'usb_kot' : 'usb_bill';

    await prefs.setString('${prefix}_name', device.name ?? '');
    await prefs.setString('${prefix}_address', device.address ?? '');
    await prefs.setString('${prefix}_vendor_id', device.vendorId ?? '');
    await prefs.setString('${prefix}_product_id', device.productId ?? '');

    if (role == PrinterRole.kot) {
      _kotName = device.name;
      _kotAddress = device.address;
      _kotVendorId = device.vendorId;
      _kotProductId = device.productId;
      _kotDevice = device;
    } else {
      _billName = device.name;
      _billAddress = device.address;
      _billVendorId = device.vendorId;
      _billProductId = device.productId;
      _billDevice = device;
    }
    
    // Set this service as the handler for this role
    await prefs.setString(role == PrinterRole.kot ? 'kot_connection_type' : 'bill_connection_type', 'usb');
    if (role == PrinterRole.kot) _kotConnectionType = PrinterConnectionType.usb;
    else _billConnectionType = PrinterConnectionType.usb;

    // Test connection
    await _connectToDevice(device, role);
    
    notifyListeners();
  }

  Future<bool> _connectToDevice(PrinterDevice device, PrinterRole role) async {
    try {
      final connected = await _printerManager.connect(
          type: PrinterType.usb, 
          model: UsbPrinterInput(
              name: device.name, 
              productId: device.productId, 
              vendorId: device.vendorId
          )
      );
      _isConnected = connected;
      if (connected) _lastConnectedRole = role;
      return connected;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _printerManager.disconnect(type: PrinterType.usb);
      _isConnected = false;
      _lastConnectedRole = null;
      notifyListeners();
    } catch (e) {
    }
  }

  Future<bool> testPrintRole(PrinterRole role) async {
    final device = role == PrinterRole.kot ? _kotDevice : _billDevice;
    if (device == null) return false;

    // Direct test print bytes
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes += generator.text("YUG POS", styles: PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.text("${role.toString().split('.').last.toUpperCase()} TEST PRINT", styles: PosStyles(align: PosAlign.center));
    bytes += generator.feed(2);
    bytes += generator.cut();

    return await printRawBytes(bytes, role: role);
  }

  Future<bool> printRawBytes(List<int> bytes, {PrinterRole role = PrinterRole.bill, bool isRetry = false}) async {
    // 1. Resolve targeting
    PrinterDevice? targetDevice = role == PrinterRole.kot ? _kotDevice : _billDevice;
    final savedName = role == PrinterRole.kot ? _kotName : _billName;
    final savedVID = role == PrinterRole.kot ? _kotVendorId : _billVendorId;
    final savedPID = role == PrinterRole.kot ? _kotProductId : _billProductId;

    // 2. Discovery recovery if device object is lost
    if (targetDevice == null && (savedName != null || savedVID != null)) {
      scan(silent: true);
      await Future.delayed(const Duration(seconds: 1));
      targetDevice = role == PrinterRole.kot ? _kotDevice : _billDevice;
    }

    if (targetDevice == null) {
      return false;
    }

    try {
      // 3. Connection Management (Switch if needed)
      if (!_isConnected || _lastConnectedRole != role) {
        _isConnected = await _connectToDevice(targetDevice, role);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // 4. Print attempt
      if (_isConnected) {
        await _printerManager.send(type: PrinterType.usb, bytes: bytes);
        return true;
      }
      return false;
    } catch (e) {
      _isConnected = false;
      _lastConnectedRole = null;
      // debugPrint("USB Printing error (Role: $role, Retry: $isRetry): $e");
      
      if (!isRetry) {
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
        return await printRawBytes(bytes, role: role, isRetry: true);
      }
      return false;
    }
  }
}
