import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;
  List<PrinterDevice> _devices = [];
  List<PrinterDevice> get devices => _devices;

  PrinterDevice? _selectedDevice;
  PrinterDevice? get selectedDevice => _selectedDevice;

  String? _savedName;
  String? _savedAddress;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;
  
  bool get hasSavedPrinter => _savedAddress != null;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _stateSubscription;

  BluetoothPrinterService() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
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
      debugPrint("Bluetooth state changed: $event");
      _isConnected = (event == BTStatus.connected);
      notifyListeners();
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _savedAddress = prefs.getString('bt_printer_address');
    _savedName = prefs.getString('bt_printer_name');
    _isConnected = false;

    // We no longer auto-connect in the constructor to avoid 
    // permission-request race conditions during app boot.
    // Connection will be established when needed or through Settings.
    if (_savedAddress != null) {
      debugPrint('[BT] Found saved printer: $_savedName');
    }
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
    
    if (!granted) {
      debugPrint("[BT] Permissions Denied: $statuses");
    }
    return granted;
  }

  void scan() async {
    if (_isScanning) return;
    
    // Check permissions first
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

    // Auto-stop scan after 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      stopScan();
    });
  }

  void stopScan() {
    _isScanning = false;
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<bool> connect(String address, {String? name}) async {
    // Check permissions first
    if (!await _checkPermissions()) return false;

    _isConnecting = true;
    notifyListeners();
    
    try {
      debugPrint("[BT] Connecting to $address (isBle: false)...");
      bool connected = await _printerManager.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          name: name ?? _savedName ?? 'Printer',
          address: address,
          isBle: false, 
        ),
      );

      // FALLBACK: If standard BT fails, try BLE
      if (!connected) {
        debugPrint("[BT] Standard connection failed. Retrying with BLE...");
        connected = await _printerManager.connect(
          type: PrinterType.bluetooth,
          model: BluetoothPrinterInput(
            name: name ?? _savedName ?? 'Printer',
            address: address,
            isBle: true, 
          ),
        );
      }
      _isConnected = connected;
      if (connected) {
        _savedAddress = address;
        _savedName = name ?? _savedName;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bt_printer_address', address);
        if (_savedName != null) await prefs.setString('bt_printer_name', _savedName!);
        
        // Find printer in discovered list to update internal object if needed
        _selectedDevice = _devices.firstWhere(
          (d) => d.address == address, 
          orElse: () => PrinterDevice(name: _savedName ?? 'Printer', address: address)
        );
      }
      _isConnecting = false;
      notifyListeners();
      return connected;
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      debugPrint("BT Connection error: $e");
      notifyListeners();
      return false;
    }
  }

  Future<void> selectDevice(PrinterDevice device) async {
    await connect(device.address!, name: device.name);
  }

  Future<void> disconnect() async {
    try {
      await _printerManager.disconnect(type: PrinterType.bluetooth);
      _selectedDevice = null;
      _isConnected = false;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bt_printer_address');
      await prefs.remove('bt_printer_name');
      _savedAddress = null;
      _savedName = null;
      
      notifyListeners();
    } catch (e) {
      debugPrint("BT Disconnect error: $e");
    }
  }

  Future<bool> printRawBytes(List<int> bytes) async {
    debugPrint('[BT] printRawBytes called. bytes=${bytes.length}, isConnected=$_isConnected, savedAddress=$_savedAddress');

    if (!_isConnected && _savedAddress != null) {
      debugPrint('[BT] Not connected — attempting auto-connect to $_savedAddress...');
      await connect(_savedAddress!);
      debugPrint('[BT] Auto-connect result: isConnected=$_isConnected');
    }

    if (!_isConnected) {
      debugPrint('[BT] ❌ Print aborted: Not connected and auto-connect failed.');
      return false;
    }

    try {
      debugPrint('[BT] Sending ${bytes.length} bytes to printer...');
      final success = await _printerManager.send(type: PrinterType.bluetooth, bytes: bytes);
      debugPrint('[BT] send() result: $success');
      return success;
    } catch (e) {
      debugPrint('[BT] ❌ Send error: $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> testPrint() async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      bytes += generator.setStyles(PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text("YUG POS", styles: PosStyles(height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text("PRINTER TEST PAGE", styles: PosStyles(bold: true));
      bytes += generator.text("Status: Connected Successfully", styles: PosStyles(bold: true));
      bytes += generator.text("Date: ${DateTime.now()}");
      bytes += generator.feed(2);
      bytes += generator.cut();

      return await printRawBytes(bytes);
    } catch (e) {
      debugPrint("Test print generation error: $e");
      return false;
    }
  }
}
