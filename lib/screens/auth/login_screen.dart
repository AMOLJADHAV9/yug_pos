import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true; // Added for password visibility toggle
  String _pinInput = '';

  // Theme Colors
  final Color _primaryYellow = const Color(0xFFFCDD22);
  final Color _bgBlack = const Color(0xFF141615);
  final Color _surfaceGrey = const Color(0xFF141615);

  void _loginEmail() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final error = await auth.loginWithEmail(_emailCtrl.text.trim(), _passCtrl.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _pinKeyPressed(String val) {
    if (_pinInput.length < 4) {
      setState(() => _pinInput += val);
      if (_pinInput.length == 4) _verifyPin();
    }
  }

  void _pinBackspace() {
    if (_pinInput.isNotEmpty) {
      setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
    }
  }
  
  void _verifyPin() {
    final auth = context.read<AuthService>();
    final success = auth.unlockWithPin(_pinInput);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Invalid PIN', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
      ));
      setState(() => _pinInput = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBlack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 800) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Moving logo here for mobile
                    Image.asset(
                      'lib/assets/img/yug-poslogo.png', 
                      width: 160, // Slightly smaller logo for more space
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(Icons.storefront, size: 80, color: _primaryYellow),
                    ),
                    const SizedBox(height: 20), // Reduced spacing
                    _buildLoginFormSection(isMobile: true),
                  ],
                ),
              ),
            );
          } else {
            return Row(
              children: [
                Expanded(flex: 5, child: _buildBrandingSection(isMobile: false)),
                Expanded(flex: 4, child: _buildLoginFormSection(isMobile: false)),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildBrandingSection({required bool isMobile}) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: isMobile ? 320 : double.infinity),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('lib/assets/img/poswelimg.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          // Dark Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_bgBlack, _bgBlack.withOpacity(0.8), _bgBlack.withOpacity(0.4)],
                begin: isMobile ? Alignment.bottomCenter : Alignment.centerRight,
                end: isMobile ? Alignment.topCenter : Alignment.centerLeft,
              ),
            ),
          ),
          
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 24.0 : 64.0,
                        vertical: constraints.maxHeight < 600 ? 32.0 : 64.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo
                          Image.asset(
                            'lib/assets/img/yug-poslogo.png', 
                            width: isMobile ? 180 : 400,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.storefront, size: 80, color: _primaryYellow),
                          ),
                          const SizedBox(height: 12),
                          // Slogan
                          Container(
                            height: 2, width: 40,
                            color: _primaryYellow,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: isMobile ? double.infinity : 400,
                            child: Text(
                              "The ultimate point-of-sale solution designed for efficiency, speed, and seamless management.",
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 14 : 18, 
                                color: Colors.white.withOpacity(0.9), 
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: isMobile ? TextAlign.center : TextAlign.left,
                            ),
                          ),
                          if (!isMobile) ...[
                            const SizedBox(height: 64),
                            Text(
                              "© ${DateTime.now().year} Yug POS. Premium Version.", 
                              style: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLoginFormSection({required bool isMobile}) {
    return Padding(
      padding: EdgeInsets.zero, // Remove additional padding for mobile
      child: Consumer<AuthService>(
        builder: (context, auth, _) {
          bool usePinMode = auth.currentUser != null && auth.hasSavedPin;
          return Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: EdgeInsets.all(isMobile ? 24 : 40),
            decoration: BoxDecoration(
                color: _surfaceGrey,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF141615).withOpacity(0.5), 
                    blurRadius: 40, 
                    offset: const Offset(0, 20)
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    usePinMode ? "Unlock Device" : "Sign In", 
                    style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white), 
                    textAlign: TextAlign.center
                  ),
                  const SizedBox(height: 8),
                  Text(
                    usePinMode ? "Enter your 4-digit security PIN" : "Enter your credentials below", 
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white54), 
                    textAlign: TextAlign.center
                  ),
                  const SizedBox(height: 40),
                  _buildFormContent(auth, usePinMode),
                ],
              ),
            );
          },
        ),
      );
  }

  Widget _buildFormContent(AuthService auth, bool usePinMode) {
     return usePinMode ? _buildPinForm(auth) : _buildEmailForm();
  }

  Widget _buildEmailForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: GoogleFonts.inter(color: Colors.white60),
            prefixIcon: const Icon(Icons.mail_outline, color: Colors.white38),
            filled: true, 
            fillColor: const Color(0xFF141615),
            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _primaryYellow, width: 1.5)),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: GoogleFonts.inter(color: Colors.white60),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _primaryYellow, width: 1.5)),
          ),
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loginEmail(),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 60,
          child: ElevatedButton(
            onPressed: _loading ? null : _loginEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryYellow,
              foregroundColor: const Color(0xFF141615),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              shadowColor: _primaryYellow.withOpacity(0.3),
            ),
            child: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: const Color(0xFF141615), strokeWidth: 3))
                : Text("SIGN IN TO DASHBOARD", style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("New to Yug POS?", style: GoogleFonts.inter(color: Colors.white38, fontSize: 14)),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              style: TextButton.styleFrom(foregroundColor: _primaryYellow),
              child: Text("Register Now", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            )
          ],
        )
      ],
    );
  }

  Widget _buildPinForm(AuthService auth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(radius: 36, backgroundColor: const Color(0xFF141615), child: Icon(Icons.person, size: 36, color: _primaryYellow)),
        const SizedBox(height: 12),
        Text(auth.currentUser?.email ?? 'User', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            bool filled = index < _pinInput.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? _primaryYellow : Colors.transparent,
                border: Border.all(color: filled ? _primaryYellow : Colors.white24, width: 2),
                boxShadow: filled ? [BoxShadow(color: _primaryYellow.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)] : [],
              ),
            );
          }),
        ),
        const SizedBox(height: 48),
        _buildNumpad(),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => auth.logout(),
          icon: Icon(Icons.logout, size: 18, color: Colors.white38),
          label: Text("Switch Account", style: GoogleFonts.inter(color: Colors.white38, fontWeight: FontWeight.w600)),
        )
      ],
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        for (var row in [[1,2,3], [4,5,6], [7,8,9]]) 
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((num) => _buildNumKey('$num')).toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 70, height: 70), // Empty space
            _buildNumKey('0'),
            _buildNumKey('backspace', icon: Icons.backspace_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildNumKey(String val, {IconData? icon}) {
    return InkWell(
      onTap: () {
        if (val == 'backspace') {
          _pinBackspace();
        } else {
          _pinKeyPressed(val);
        }
      },
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF141615),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: val == 'backspace'
              ? Icon(icon, size: 24, color: _primaryYellow)
              : Text(val, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ),
    );
  }
}
