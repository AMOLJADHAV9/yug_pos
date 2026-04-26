import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiService extends ChangeNotifier {
  List<WifiNetwork> _networks = [];
  List<WifiNetwork> get networks => _networks;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String? _currentSsid;
  String? get currentSsid => _currentSsid;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  WifiService() {
    if (!kIsWeb && Platform.isAndroid) {
      _init();
    }
  }

  Future<void> _init() async {
    _currentSsid = await WiFiForIoTPlugin.getSSID();
    _isConnected = await WiFiForIoTPlugin.isConnected();
    notifyListeners();
  }

  Future<bool> checkPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    if (statuses[Permission.location]!.isGranted) {
      if (Platform.isAndroid && await Permission.location.serviceStatus.isDisabled) {
        // Location service is off
        return false;
      }
      return true;
    }
    
    // For Android 13+ we might need nearby devices permission
    if (statuses[Permission.nearbyWifiDevices] == null) {
       await Permission.nearbyWifiDevices.request();
    }

    return statuses[Permission.location]!.isGranted;
  }

  Future<void> scanNetworks() async {
    if (_isScanning) return;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      return;
    }

    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    _isScanning = true;
    _networks = [];
    notifyListeners();

    try {
      bool isEnabled = await WiFiForIoTPlugin.isEnabled();
      if (!isEnabled) {
        await WiFiForIoTPlugin.setEnabled(true);
        // Wait a bit for WiFi to turn on
        await Future.delayed(const Duration(seconds: 2));
      }

      final list = await WiFiForIoTPlugin.loadWifiList();
      _networks = list ?? [];
    } catch (e) {
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> connect(String ssid, String password) async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    
    try {
      final success = await WiFiForIoTPlugin.connect(
        ssid,
        password: password,
        security: NetworkSecurity.WPA, // Most common
        joinOnce: false,
      );

      if (success) {
        await WiFiForIoTPlugin.forceWifiUsage(true);
        _currentSsid = ssid;
        _isConnected = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> disconnect() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    
    try {
      await WiFiForIoTPlugin.disconnect();
      await WiFiForIoTPlugin.forceWifiUsage(false);
      _currentSsid = null;
      _isConnected = false;
      notifyListeners();
    } catch (e) {
    }
  }

  Future<void> refreshStatus() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    try {
      _currentSsid = await WiFiForIoTPlugin.getSSID();
      _isConnected = await WiFiForIoTPlugin.isConnected();
      notifyListeners();
    } catch (e) {
    }
  }
}
