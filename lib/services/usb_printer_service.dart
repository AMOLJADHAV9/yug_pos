import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsbPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;
  List<PrinterDevice> _devices = [];
  List<PrinterDevice> get devices => _devices;

  PrinterDevice? _selectedDevice;
  PrinterDevice? get selectedDevice => _selectedDevice;

  String? _savedName;
  String? _savedAddress;
  String? _savedVendorId;
  String? _savedProductId;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  bool get hasSavedPrinter => _savedName != null || _savedVendorId != null;

  StreamSubscription? _scanSubscription;
  Timer? _heartbeatTimer;

  UsbPrinterService() {
    _init();
    // Periodic heartbeat to keep device list fresh
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) => scan(silent: true));
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _savedAddress = prefs.getString('usb_printer_address');
    _savedName = prefs.getString('usb_printer_name');
    _savedVendorId = prefs.getString('usb_printer_vendor_id');
    _savedProductId = prefs.getString('usb_printer_product_id');
    
    // Ensure we start disconnected in state
    _isConnected = false;

    if (_savedAddress != null && _savedName != null) {
      debugPrint("Restored printer setting: $_savedName at $_savedAddress");
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
      
      // Auto-reconnect if we found our saved device and nothing is selected
      if (_selectedDevice == null && (_savedName != null || _savedVendorId != null)) {
        if (event.name == _savedName || event.address == _savedAddress || 
            (event.vendorId == _savedVendorId && event.productId == _savedProductId)) {
           debugPrint("Automatically re-discovered printer: ${event.name}");
           await selectDevice(event);
        }
      }
      
      notifyListeners();
    });

    if (!silent) {
      Future.delayed(const Duration(seconds: 10), () {
        stopScan();
      });
    }
  }

  void stopScan() {
    _isScanning = false;
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<void> selectDevice(PrinterDevice device) async {
    _selectedDevice = device;
    _savedAddress = device.address;
    _savedName = device.name;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usb_printer_address', device.address ?? '');
    await prefs.setString('usb_printer_name', device.name ?? '');
    await prefs.setString('usb_printer_vendor_id', device.vendorId ?? '');
    await prefs.setString('usb_printer_product_id', device.productId ?? '');
    
    _savedAddress = device.address;
    _savedName = device.name;
    _savedVendorId = device.vendorId;
    _savedProductId = device.productId;
    
    // Explicitly connect when selected
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
      debugPrint("Connection attempt to ${device.name}: $_isConnected");
    } catch (e) {
      _isConnected = false;
      debugPrint("Initial connection error: $e");
    }
    
    notifyListeners();
  }

  /// Disconnect current printer
  Future<void> disconnect() async {
    if (_selectedDevice != null) {
      try {
        await _printerManager.disconnect(type: PrinterType.usb);
        _selectedDevice = null;
        _isConnected = false;
        notifyListeners();
      } catch (e) {
        debugPrint("Disconnect error: $e");
      }
    }
  }

  Future<bool> printRawBytes(List<int> bytes, {bool isRetry = false}) async {
    // 1. Discovery recovery
    if (_selectedDevice == null && (_savedName != null || _savedVendorId != null)) {
      debugPrint("No active printer object. Re-scanning...");
      scan(silent: true);
      await Future.delayed(const Duration(seconds: 2));
      
      for (final p in _devices) {
        if (p.name == _savedName || p.address == _savedAddress || 
            (p.vendorId == _savedVendorId && p.productId == _savedProductId)) {
          _selectedDevice = p;
          break;
        }
      }
    }

    final device = _selectedDevice;
    if (device == null) {
      debugPrint("Print failed: Printer not found.");
      return false;
    }

    try {
      // 2. Aggressive Connection
      if (!_isConnected) {
        debugPrint("Printer offline. Attempting reconnection to ${device.name}...");
        _isConnected = await _printerManager.connect(
            type: PrinterType.usb, 
            model: UsbPrinterInput(
                name: device.name, 
                productId: device.productId, 
                vendorId: device.vendorId
            )
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // 3. Print attempt
      if (_isConnected) {
        await _printerManager.send(type: PrinterType.usb, bytes: bytes);
        debugPrint("SUCCESS: Print data sent.");
        return true;
      }
      return false;
    } catch (e) {
      _isConnected = false;
      debugPrint("Printing error (isRetry: $isRetry): $e");
      
      // 4. One-time retry on failure
      if (!isRetry) {
        debugPrint("Attempting one-time reconnect and retry...");
        await _printerManager.disconnect(type: PrinterType.usb);
        await Future.delayed(const Duration(seconds: 1));
        return await printRawBytes(bytes, isRetry: true);
      }
      
      return false;
    }
  }
}
