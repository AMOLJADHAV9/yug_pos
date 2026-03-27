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
import 'screens/auth/unauthorized_screen.dart';

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
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: !kIsWeb, // Disable ONLY on web to avoid assertion errors
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

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
      ],
      child: MaterialApp(
        title: 'YUG POS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE7FF12),
            onPrimary: Colors.black,
            secondary: Color(0xFFE7FF12),
            surface: Color(0xFF121212),
            background: Colors.black,
            onSurface: Colors.white,
          ),
          scaffoldBackgroundColor: Colors.black,
          cardTheme: CardThemeData(
            color: const Color(0xFF1E1E1E),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            centerTitle: true,
            elevation: 0,
            titleTextStyle: TextStyle(color: Color(0xFFE7FF12), fontSize: 20, fontWeight: FontWeight.bold),
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.black,
            selectedItemColor: Color(0xFFE7FF12),
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (auth.isUnlocked) {
          if (auth.role == UserRole.admin) {
            return const AdminDashboard();
          } else if (auth.role == UserRole.cashier) {
            return const CashierDashboard();
          } else if (auth.role == UserRole.waiter) {
            return const TablesScreen();
          }
          return const UnauthorizedScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
