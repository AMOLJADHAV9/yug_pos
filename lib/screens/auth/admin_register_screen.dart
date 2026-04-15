import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/navigator_utils.dart';

class AdminRegisterScreen extends StatefulWidget {
  const AdminRegisterScreen({super.key});

  @override
  State<AdminRegisterScreen> createState() => _AdminRegisterScreenState();
}

class _AdminRegisterScreenState extends State<AdminRegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _restaurantNameCtrl = TextEditingController(); // Added
  bool _loading = false;
  
  void _registerAdmin() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty || _nameCtrl.text.isEmpty || _restaurantNameCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final error = await auth.registerWithEmail(
      email: _emailCtrl.text.trim(), 
      password: _passCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      restaurantName: _restaurantNameCtrl.text.trim(), // Added
      role: 'admin',
    );
    
    if (mounted) {
      setState(() => _loading = false);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Admin Account & Restaurant Created!'),
          backgroundColor: Colors.green,
        ));
        safePop(context); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Admin Registration'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.blueAccent.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))
                ],
                border: Border.all(color: Colors.blueAccent.withOpacity(0.2))
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   const Icon(Icons.admin_panel_settings, size: 48, color: Colors.blueAccent),
                  const SizedBox(height: 16),
                  const Text("Admin Registration", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                  const SizedBox(height: 8),
                  Text("Create a master dashboard account", style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center,),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _restaurantNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Restaurant Name',
                      prefixIcon: const Icon(Icons.restaurant_menu),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Admin Name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCtrl,
                    decoration: InputDecoration(
                      labelText: 'Admin Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    decoration: InputDecoration(
                      labelText: 'Admin Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _registerAdmin(),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _loading ? null : _registerAdmin,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: _loading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("CREATE ADMIN ACCOUNT", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
