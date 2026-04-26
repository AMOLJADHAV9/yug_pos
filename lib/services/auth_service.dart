import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { waiter, admin, cashier, none }

// ─── Windows REST API Auth ────────────────────────────────────────────────────
// firebase_auth Windows plugin crashes (fires id-token events on a background
// C++ thread). We bypass the plugin entirely on Windows and call Firebase
// Auth REST API directly.
const String _kFirebaseApiKey   = 'AIzaSyBo49QOZeqakwO6Tq3ZZ5HcD014hxnrb4c';
const String _kFirebaseProject  = 'ldma-pos';

class AuthService extends ChangeNotifier {
  // On Desktop/Windows: _auth is null; we use REST API instead.
  final FirebaseAuth?   _auth;
  final FirebaseFirestore _firestore;

  // Windows REST session
  String? _windowsIdToken;
  String? _windowsUid;
  String? _windowsEmail;

  bool get _isWindowsMode => !kIsWeb && Platform.isWindows;

  User? get currentUser {
    if (_isWindowsMode) return null; // no plugin user on Windows
    return _auth?.currentUser;
  }

  String? get currentEmail => _isWindowsMode ? _windowsEmail : _auth?.currentUser?.email;

  bool _isUnlocked = false;
  bool get isUnlocked => _isUnlocked;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  UserRole _role = UserRole.none;
  UserRole get role => _role;

  String? _restaurantId;
  String? get restaurantId => _restaurantId;

  String? _restaurantName;
  String? _userName;
  String? get restaurantName => _restaurantName;
  String? get userName => _userName;

  String? _savedPin;
  bool get hasSavedPin => _savedPin != null;

  Timer? _sessionTimer;

  AuthService({required FirebaseAuth? auth, required FirebaseFirestore firestore})
      : _auth = auth,
        _firestore = firestore {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedPin = prefs.getString('waiter_pin');

      if (_isWindowsMode) {
        // Windows: no persistent session, start at login screen
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Mobile / Web: standard streaming listener
      _auth!.authStateChanges().listen((user) async {
        _isLoading = true;
        notifyListeners();
        if (user == null) {
          _isUnlocked = false;
          _restaurantId = null;
          _role = UserRole.none;
          _stopSessionTimer();
          _isLoading = false;
        } else {
          await _loadProfile(user.uid);
        }
        notifyListeners();
      });
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches Firestore profile and sets state. Used on mobile after auth.
  Future<void> _loadProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        _isUnlocked = false;
        _isLoading = false;
        return;
      }
      final data = doc.data()!;
      _role = _getRoleFromString(data['role'] ?? 'waiter');
      _restaurantId = data['restaurantId'];
      _userName = data['name'];
      if (_restaurantId != null) {
        final resDoc = await _firestore.collection('restaurants').doc(_restaurantId).get();
        _restaurantName = resDoc.data()?['name'];
      }
      _isUnlocked = _savedPin == null ? true : false;
      if (_savedPin == null) _startSessionTimer();
      _isLoading = false;
    } catch (e) {
      _isUnlocked = _savedPin == null;
      _isLoading = false;
    }
  }

  // ─── Windows REST Login ──────────────────────────────────────────────────
  Future<String?> _loginWindows(String email, String password) async {
    try {
      final authRes = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_kFirebaseApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password, 'returnSecureToken': true}),
      );
      final authBody = jsonDecode(authRes.body);
      if (authRes.statusCode != 200) {
        final msg = authBody['error']?['message'] ?? 'Login failed';
        return '[auth] $msg';
      }
      _windowsIdToken = authBody['idToken'];
      _windowsUid     = authBody['localId'];
      _windowsEmail   = email;

      // Fetch user profile via Firestore plugin
      final doc = await _firestore.collection('users').doc(_windowsUid).get();
      if (!doc.exists) return 'Access Denied: User profile not found.';
      final data = doc.data()!;
      _role         = _getRoleFromString(data['role'] ?? 'waiter');
      _restaurantId = data['restaurantId'];
      _userName     = data['name'];
      if (_restaurantId != null) {
        final resDoc = await _firestore.collection('restaurants').doc(_restaurantId).get();
        _restaurantName = resDoc.data()?['name'];
      }
      _isUnlocked = true;
      _startSessionTimer();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ─── Public API ──────────────────────────────────────────────────────────
  Future<String?> loginWithEmail(String email, String password) async {
    if (_isWindowsMode) return _loginWindows(email, password);
    try {
      final cred = await _auth!.signInWithEmailAndPassword(email: email, password: password);
      final doc  = await _firestore.collection('users').doc(cred.user!.uid).get();
      if (!doc.exists) { await _auth.signOut(); return 'Access Denied.'; }
      final data = doc.data()!;
      _role         = _getRoleFromString(data['role'] ?? 'waiter');
      _restaurantId = data['restaurantId'];
      _userName     = data['name'];
      if (_restaurantId != null) {
        final resDoc = await _firestore.collection('restaurants').doc(_restaurantId).get();
        _restaurantName = resDoc.data()?['name'];
      }
      _isUnlocked = true;
      _startSessionTimer();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return '[${e.code}] ${e.message}';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> registerWithEmail({
    required String email, required String password, required String name,
    required String restaurantName, String? address, String? state,
    String? gstNumber, double cgst = 2.5, double sgst = 2.5, String role = 'admin',
  }) async {
    try {
      final cred = await _auth!.createUserWithEmailAndPassword(email: email, password: password);
      final resDoc = await _firestore.collection('restaurants').add({
        'name': restaurantName, 'address': address, 'state': state,
        'gstNumber': gstNumber, 'cgst': cgst, 'sgst': sgst,
        'createdAt': FieldValue.serverTimestamp(), 'adminUid': cred.user!.uid,
      });
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'email': email, 'name': name, 'role': role,
        'restaurantId': resDoc.id, 'createdAt': FieldValue.serverTimestamp(),
      });
      _role = _getRoleFromString(role);
      _restaurantId = resDoc.id;
      _restaurantName = restaurantName;
      _isUnlocked = true;
      _startSessionTimer();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return '[${e.code}] ${e.message}';
    } catch (e) {
      return e.toString();
    }
  }

  bool unlockWithPin(String pin) {
    if (pin == _savedPin && (_windowsUid != null || currentUser != null)) {
      _isUnlocked = true;
      _startSessionTimer();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waiter_pin', pin);
    _savedPin = pin;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('waiter_pin');
    _savedPin = null;
    _isUnlocked = false;
    _role = UserRole.none;
    _restaurantId = null;
    _restaurantName = null;
    _userName = null;
    _windowsIdToken = null;
    _windowsUid     = null;
    _windowsEmail   = null;
    _stopSessionTimer();
    if (!_isWindowsMode) await _auth?.signOut();
    notifyListeners();
  }

  Future<void> lockSession() async {
    if (_savedPin != null) {
      _isUnlocked = false;
      _stopSessionTimer();
      notifyListeners();
    } else {
      await logout();
    }
  }

  void _startSessionTimer() {
    _stopSessionTimer();
    _sessionTimer = Timer(const Duration(hours: 12), logout);
  }

  void _stopSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  Future<String?> adminCreateUser({
    required String email, required String password,
    required String name,  required String role,
    String? phone, String? pin,
  }) async {
    // 1. Check for Waiter Limits (Max 2 per restaurant)
    if (role == 'waiter' && _restaurantId != null) {
      try {
        final waiterQuery = await _firestore.collection('users')
            .where('restaurantId', isEqualTo: _restaurantId)
            .where('role', isEqualTo: 'waiter')
            .get();
        
        if (waiterQuery.docs.length >= 2) {
          return "Maximum limit of 2 Waiter accounts reached for this restaurant.";
        }
      } catch (e) {
        // Proceeding anyway if query fails? No, better safe than sorry.
        return "Failed to verify staff limits. Please try again.";
      }
    }

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(email: email, password: password);
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'name': name, 'email': email, 'role': role,
        'restaurantId': _restaurantId, 'phone': phone, 'pin': pin,
        'status': 'active', 'createdAt': FieldValue.serverTimestamp(),
      });
      await secondaryAuth.signOut();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    } finally {
      await secondaryApp?.delete();
    }
  }

  Future<void> updateStaffStatus(String uid, bool isActive) async {
    await _firestore.collection('users').doc(uid).update({'status': isActive ? 'active' : 'inactive'});
  }

  Future<void> sendResetEmail(String email) async {
    await _auth?.sendPasswordResetEmail(email: email);
  }

  void userActivityDetected() {
    if (_isUnlocked) _startSessionTimer();
  }

  UserRole _getRoleFromString(String r) {
    switch (r) {
      case 'admin':   return UserRole.admin;
      case 'cashier': return UserRole.cashier;
      case 'waiter':  return UserRole.waiter;
      default:        return UserRole.waiter;
    }
  }
}
