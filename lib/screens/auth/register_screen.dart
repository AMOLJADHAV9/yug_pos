import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/navigator_utils.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _resNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController(); // Added address
  final _gstCtrl = TextEditingController(); // Added GST Controller
  final _cgstCtrl = TextEditingController(text: "2.5"); 
  final _sgstCtrl = TextEditingController(text: "2.5");
  bool _loading = false;
  bool _obscurePassword = true;
  // List of Indian States & UTs
  static const List<String> _indianStates = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 
    'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 
    'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 
    'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
    'Andaman and Nicobar', 'Chandigarh', 'Dadra & Nagar Haveli', 'Delhi', 
    'Jammu & Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry'
  ];

  String _selectedState = 'Maharashtra';

  void _register() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty || _nameCtrl.text.isEmpty || _resNameCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final error = await auth.registerWithEmail(
      email: _emailCtrl.text.trim(), 
      password: _passCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      restaurantName: _resNameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      state: _selectedState, // Pass State
      gstNumber: _gstCtrl.text.trim(),
      cgst: double.tryParse(_cgstCtrl.text.trim()) ?? 2.5,
      sgst: double.tryParse(_sgstCtrl.text.trim()) ?? 2.5,
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
          content: Text('Registration successful!'),
          backgroundColor: Colors.green,
        ));
        safePop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141615),
      appBar: AppBar(
        title: const Text('Register Account'),
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
                color: const Color(0xFF141615),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF141615).withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))
                ]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/yug-poslogo.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  const Text("Create Admin Account", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center,),
                  const SizedBox(height: 8),
                  const Text("Register your restaurant dashboard", style: TextStyle(color: Colors.white54), textAlign: TextAlign.center,),
                  const SizedBox(height: 32),
                  _buildTextField(_nameCtrl, 'Full Name', Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildTextField(_resNameCtrl, 'Restaurant Name', Icons.restaurant),
                  const SizedBox(height: 16),
                  _buildTextField(_addressCtrl, 'Restaurant Address', Icons.location_on_outlined),
                  const SizedBox(height: 16),
                  
                  // State Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedState,
                    isExpanded: true, // Fix horizontal overflow
                    dropdownColor: const Color(0xFF141615),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'State',
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.map_outlined, color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF141615),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFCDD22))),
                    ),
                    items: _indianStates.map((state) => DropdownMenuItem(
                      value: state,
                      child: Text(state, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedState = val!),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildTextField(_emailCtrl, 'Email', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  _buildTextField(_gstCtrl, 'GST Number (Optional)', Icons.receipt_long_outlined),
                  const SizedBox(height: 16),
                  
                  // CGST & SGST Percentages
                  Row(
                    children: [
                      Expanded(child: _buildTextField(_cgstCtrl, 'CGST (%)', Icons.percent, keyboardType: TextInputType.number)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField(_sgstCtrl, 'SGST (%)', Icons.percent, keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _passCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.white38,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF141615),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFCDD22))),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _register(),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _loading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: const Color(0xFFFCDD22),
                      foregroundColor: const Color(0xFF141615),
                    ),
                    child: _loading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: const Color(0xFF141615), strokeWidth: 2))
                        : const Text("REGISTER ACCOUNT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF141615),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFCDD22))),
      ),
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
    );
  }
}


