import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/tables_screen.dart';
import 'providers/cart_provider.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/cashier/cashier_dashboard.dart';
import 'screens/cashier/cashier_dashboard_v2.dart';
import 'screens/auth/unauthorized_screen.dart';
import 'services/usb_printer_service.dart';
import 'services/bluetooth_printer_service.dart';
import 'services/wifi_service.dart';
import 'utils/navigator_utils.dart';

class GlobalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Specifically allow Google Trust Services certificates if validation fails on older devices
        if (cert.issuer.contains("Google Trust Services")) {
          return true;
        }
        return false; // Maintain security for other domains
      };
  }
}

void main() async {
  HttpOverrides.global = GlobalHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
  
  runApp(const WaiterPosApp());
}

class WaiterPosApp extends StatelessWidget {
  const WaiterPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => UsbPrinterService()),
        ChangeNotifierProvider(create: (_) => BluetoothPrinterService()),
        ChangeNotifierProvider(create: (_) => WifiService()),
      ],
      child: MaterialApp(
        // Removed navigatorKey temporarily to fix "Empty History" crash
        // navigatorKey: rootNavigatorKey, 
        title: 'YUG POS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFCDD22),
            onPrimary: Color(0xFF141615),
            secondary: Color(0xFFFCDD22),
            surface: Color(0xFF141615),
            background: Color(0xFF141615),
            onSurface: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFF141615),
          cardTheme: CardThemeData(
            color: const Color(0xFF1A1C1B),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF141615),
            centerTitle: true,
            elevation: 0,
            titleTextStyle: TextStyle(color: Color(0xFFFCDD22), fontSize: 20, fontWeight: FontWeight.bold),
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Color(0xFF141615),
            selectedItemColor: Color(0xFFFCDD22),
            unselectedItemColor: Colors.grey,
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
            displayLarge: GoogleFonts.inter(color: Colors.white),
            bodyLarge: GoogleFonts.inter(color: Colors.white),
            bodyMedium: GoogleFonts.inter(color: Colors.white70),
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (auth.isLoading) {
          return Scaffold(
            backgroundColor: const Color(0xFF141615),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'lib/assets/img/Yug pos logo1_page-0001.jpg',
                    width: 250,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => 
                        const Icon(Icons.storefront, size: 80, color: Color(0xFFFCDD22)),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: Color(0xFFFCDD22)),
                ],
              ),
            ),
          );
        }
        if (auth.isUnlocked) {
          if (auth.role == UserRole.admin) {
            return const AdminDashboard();
          } else if (auth.role == UserRole.cashier || auth.role == UserRole.waiter) {
            return const CashierDashboardV2();
          }
          return const UnauthorizedScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
