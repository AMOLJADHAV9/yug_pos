import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../models/printer_role.dart';

class BluetoothPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;
  List<PrinterDevice> _devices = [];
  List<PrinterDevice> get devices => _devices;

  PrinterDevice? _selectedDevice;
  PrinterDevice? get selectedDevice => _selectedDevice;

  // Role-specific saved settings
  String? _kotAddress;
  String? _kotName;
  String? _billAddress;
  String? _billName;

  PrinterConnectionType _kotConnectionType = PrinterConnectionType.bluetooth;
  PrinterConnectionType _billConnectionType = PrinterConnectionType.bluetooth;

  PrinterConnectionType get kotConnectionType => _kotConnectionType;
  PrinterConnectionType get billConnectionType => _billConnectionType;

  String? get kotName => _kotName;
  String? get billName => _billName;
  String? get kotAddress => _kotAddress;
  String? get billAddress => _billAddress;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  String? _lastConnectedName;
  String? get lastConnectedName => _lastConnectedName ?? (selectedDevice?.name);

  bool get hasSavedPrinter => _billAddress != null || _kotAddress != null;
  bool get arePrintersConfigured => _kotAddress != null && _billAddress != null;
  bool hasRolePrinter(PrinterRole role) => role == PrinterRole.kot ? _kotAddress != null : _billAddress != null;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _stateSubscription;

  BluetoothPrinterService() {
    if (!kIsWeb) {
      _init();
      _listenToState();
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _stateSubscription?.cancel();
    super.dispose();
  }

  void _listenToState() {
    _stateSubscription = _printerManager.stateBluetooth.listen((event) {
      _isConnected = (event == BTStatus.connected);
      notifyListeners();
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Migration: if old single printer exists, move it to Billing role
    final oldAddress = prefs.getString('bt_printer_address');
    final oldName = prefs.getString('bt_printer_name');

    _kotAddress = prefs.getString('bt_kot_address');
    _kotName = prefs.getString('bt_kot_name');
    _billAddress = prefs.getString('bt_bill_address') ?? oldAddress;
    _billName = prefs.getString('bt_bill_name') ?? oldName;
    
    // Load connection types
    final kotTypeStr = prefs.getString('kot_connection_type') ?? 'bluetooth';
    final billTypeStr = prefs.getString('bill_connection_type') ?? 'bluetooth';
    _kotConnectionType = PrinterConnectionType.values.firstWhere((e) => e.toString().split('.').last == kotTypeStr, orElse: () => PrinterConnectionType.bluetooth);
    _billConnectionType = PrinterConnectionType.values.firstWhere((e) => e.toString().split('.').last == billTypeStr, orElse: () => PrinterConnectionType.bluetooth);
    
    _isConnected = false;
  }

  Future<bool> _checkPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    bool granted = statuses[Permission.bluetoothScan]?.isGranted == true &&
                   statuses[Permission.bluetoothConnect]?.isGranted == true;
    
    return granted;
  }

  void scan() async {
    if (_isScanning) return;
    if (!await _checkPermissions()) return;

    _devices.clear();
    _isScanning = true;
    notifyListeners();

    _scanSubscription?.cancel();
    _scanSubscription = _printerManager.discovery(type: PrinterType.bluetooth).listen((PrinterDevice event) {
      final index = _devices.indexWhere((p) => p.address == event.address);
      if (index < 0) {
        _devices.add(event);
      } else {
        _devices[index] = event;
      }
      notifyListeners();
    });

    Future.delayed(const Duration(seconds: 15), () => stopScan());
  }

  void stopScan() {
    _isScanning = false;
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<bool> connect(String address, {String? name}) async {
    if (!await _checkPermissions()) return false;

    // Avoid redundant connections
    if (_isConnected && _selectedDevice?.address == address) return true;

    _isConnecting = true;
    notifyListeners();
    
    try {
      bool connected = await _printerManager.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          name: name ?? 'Printer',
          address: address,
          isBle: false, 
        ),
      );

      if (!connected) {
        connected = await _printerManager.connect(
          type: PrinterType.bluetooth,
          model: BluetoothPrinterInput(name: name ?? 'Printer', address: address, isBle: true),
        );
      }

      _isConnected = connected;
      if (connected) {
        _selectedDevice = PrinterDevice(name: name ?? 'Printer', address: address);
        _lastConnectedName = name ?? 'Printer';
      }
      _isConnecting = false;
      notifyListeners();
      return connected;
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> saveRolePrinter(PrinterDevice device, PrinterRole role) async {
    final prefs = await SharedPreferences.getInstance();
    if (role == PrinterRole.kot) {
      _kotAddress = device.address;
      _kotName = device.name;
      await prefs.setString('bt_kot_address', _kotAddress!);
      await prefs.setString('bt_kot_name', _kotName!);
    } else {
      _billAddress = device.address;
      _billName = device.name;
      await prefs.setString('bt_bill_address', _billAddress!);
      await prefs.setString('bt_bill_name', _billName!);
    }
    
    // Set this service as the handler for this role
    await prefs.setString(role == PrinterRole.kot ? 'kot_connection_type' : 'bill_connection_type', 'bluetooth');
    if (role == PrinterRole.kot) _kotConnectionType = PrinterConnectionType.bluetooth;
    else _billConnectionType = PrinterConnectionType.bluetooth;

    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      await _printerManager.disconnect(type: PrinterType.bluetooth);
      _selectedDevice = null;
      _isConnected = false;
      notifyListeners();
    } catch (e) {
    }
  }

  Future<bool> printRoleBytes(List<int> bytes, PrinterRole role) async {
    final address = role == PrinterRole.kot ? _kotAddress : _billAddress;
    final name = role == PrinterRole.kot ? _kotName : _billName;

    if (address == null) {
      return false;
    }

    try {
      _lastConnectedName = name; // Update for status bar during printing
      notifyListeners();

      final connected = await connect(address, name: name);
      if (!connected) return false;

      final success = await _printerManager.send(type: PrinterType.bluetooth, bytes: bytes);
      
      // Delay slightly before disconnect to ensure buffer is sent
      await Future.delayed(const Duration(milliseconds: 500));
      await disconnect();
      
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> testPrintRole(PrinterRole role) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text("YUG POS - TEST", styles: const PosStyles(height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text("ROLE: ${role.toString().split('.').last.toUpperCase()}");
      bytes += generator.text("Status: Connected Successfully");
      bytes += generator.text("Date: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}");
      bytes += generator.feed(2);
      bytes += generator.cut();

      return await printRoleBytes(bytes, role);
    } catch (e) {
      return false;
    }
  }

  // --- COMPATIBILITY WRAPPERS (LEGACY) ---
  @Deprecated('Use saveRolePrinter instead')
  Future<void> selectDevice(PrinterDevice device) async {
    await saveRolePrinter(device, PrinterRole.bill);
  }

  @Deprecated('Use testPrintRole instead')
  Future<bool> testPrint() async {
    return testPrintRole(PrinterRole.bill);
  }
}

