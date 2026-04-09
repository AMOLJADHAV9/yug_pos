import 'dart:ui'; // Required for BackdropFilter
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

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String _pinInput = '';
  
  late final AnimationController _animCtrl = AnimationController(
    vsync: this, 
    duration: const Duration(milliseconds: 1200)
  );
  late final Animation<double> _fadeAnim = CurvedAnimation(
    parent: _animCtrl, 
    curve: Curves.easeOut
  );
  late final Animation<Offset> _slideAnim = Tween<Offset>(
    begin: const Offset(0, 0.1), 
    end: Offset.zero
  ).animate(
    CurvedAnimation(
      parent: _animCtrl, 
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic)
    ),
  );

  // Theme Colors - Premium Palette
  final Color _primaryYellow = const Color(0xFFFCDD22);
  final Color _bgBlack = const Color(0xFF0F1110); // Deeper black
  final Color _glassColor = Colors.white.withOpacity(0.04);
  final Color _glassBorder = Colors.white.withOpacity(0.1);

  @override
  void initState() {
    super.initState();
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

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
        backgroundColor: Colors.redAccent.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
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
        backgroundColor: Colors.redAccent.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
      ));
      setState(() => _pinInput = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBlack,
      body: Stack(
        children: [
          // Background Gradient Animation/Shapes
          _buildBackgroundVisuals(),
          
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 64, 24, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: _buildLogo(isMobile: true),
                        ),
                        const SizedBox(height: 48),
                        SlideTransition(
                          position: _slideAnim,
                          child: FadeTransition(
                            opacity: _fadeAnim,
                            child: _buildLoginFormSection(isMobile: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                return Row(
                  children: [
                    Expanded(flex: 5, child: _buildBrandingSection()),
                    Expanded(
                      flex: 4, 
                      child: Center(
                        child: SlideTransition(
                          position: _slideAnim,
                          child: FadeTransition(
                            opacity: _fadeAnim,
                            child: _buildLoginFormSection(isMobile: false),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundVisuals() {
    return Stack(
      children: [
        // Top-right glowing orb
        Positioned(
          top: -100, right: -100,
          child: Container(
            width: 400, height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_primaryYellow.withOpacity(0.08), Colors.transparent],
              ),
            ),
          ),
        ),
        // Bottom-left glowing orb
        Positioned(
          bottom: -150, left: -50,
          child: Container(
            width: 500, height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [const Color(0xFF14D4A4).withOpacity(0.05), Colors.transparent], // Subtle emerald hint
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo({required bool isMobile}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryYellow.withOpacity(0.2),
                blurRadius: 40,
                spreadRadius: 5,
              )
            ],
          ),
          child: Image.asset(
            'lib/assets/img/yug-poslogo.png', 
            width: isMobile ? 180 : 380,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(Icons.storefront, size: 80, color: _primaryYellow),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandingSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 64.0),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('lib/assets/img/poswelimg.jpg'),
          fit: BoxFit.cover,
          opacity: 0.15,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: _buildLogo(isMobile: false),
          ),
          const SizedBox(height: 32),
          // Slogan with premium typography
          _buildSloganLine(),
          const SizedBox(height: 24),
          Text(
            "The ultimate point-of-sale solution designed for efficiency, speed, and seamless management.",
            style: GoogleFonts.outfit(
              fontSize: 20, 
              color: Colors.white.withOpacity(0.7), 
              height: 1.6,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 80),
          Text(
            "© ${DateTime.now().year} Yug POS. Premium v2.0", 
            style: GoogleFonts.inter(color: Colors.white12, fontSize: 13, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildSloganLine() {
    return Row(
      children: [
        Container(
          height: 3, width: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(colors: [_primaryYellow, _primaryYellow.withOpacity(0.5)]),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          "Next-Gen POS Intelligence",
          style: GoogleFonts.outfit(
            color: _primaryYellow,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
  
  Widget _buildLoginFormSection({required bool isMobile}) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        bool usePinMode = auth.currentUser != null && auth.hasSavedPin;
        return ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 440,
              padding: EdgeInsets.all(isMobile ? 32 : 48),
              decoration: BoxDecoration(
                color: _glassColor,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: _glassBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    usePinMode ? "Unlock Device" : "Welcome Back", 
                    style: GoogleFonts.outfit(
                      fontSize: 32, 
                      fontWeight: FontWeight.w700, 
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ), 
                    textAlign: isMobile ? TextAlign.center : TextAlign.left,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    usePinMode ? "Enter security PIN to continue" : "Please sign in to your dashboard", 
                    style: GoogleFonts.inter(fontSize: 15, color: Colors.white38), 
                    textAlign: isMobile ? TextAlign.center : TextAlign.left,
                  ),
                  const SizedBox(height: 48),
                  _buildFormContent(auth, usePinMode),
                ],
              ),
            ),
          ),
        );
      },
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
        _buildTextField(
          controller: _emailCtrl,
          label: 'Email Address',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _passCtrl,
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          onSubmitted: (_) => _loginEmail(),
        ),
        const SizedBox(height: 40),
        // Modern Action Button
        _buildSubmitButton(
          label: "SIGN IN TO DASHBOARD",
          onPressed: _loading ? null : _loginEmail,
          isLoading: _loading,
        ),
        const SizedBox(height: 32),
        _buildRegistrationLink(),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          obscureText: isPassword && _obscurePassword,
          keyboardType: keyboardType,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.white24, size: 20),
            suffixIcon: isPassword ? IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white24,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ) : null,
            filled: true, 
            fillColor: Colors.white.withOpacity(0.03),
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _primaryYellow.withOpacity(0.5), width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryYellow.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryYellow,
          foregroundColor: const Color(0xFF0F1110),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFF0F1110), strokeWidth: 3))
            : Text(label, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    );
  }

  Widget _buildRegistrationLink() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text("New to Yug POS?", style: GoogleFonts.inter(color: Colors.white24, fontSize: 13)),
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
          style: TextButton.styleFrom(foregroundColor: _primaryYellow),
          child: Text("Register Now", style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
        )
      ],
    );
  }

  Widget _buildPinForm(AuthService auth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _primaryYellow.withOpacity(0.3), width: 2)),
          child: CircleAvatar(radius: 40, backgroundColor: Colors.white.withOpacity(0.05), child: Icon(Icons.person_outline_rounded, size: 40, color: _primaryYellow)),
        ),
        const SizedBox(height: 16),
        Text(auth.currentUser?.email ?? 'Authorized User', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 48),
        // Interactive PIN dots
        _buildPinDots(),
        const SizedBox(height: 56),
        _buildNumpad(),
        const SizedBox(height: 40),
        TextButton(
          onPressed: () => auth.logout(),
          child: Text("Switch to another account", style: GoogleFonts.inter(color: Colors.white24, fontSize: 13)),
        )
      ],
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        bool filled = index < _pinInput.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 14),
          width: 14, height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? _primaryYellow : Colors.transparent,
            border: Border.all(color: filled ? _primaryYellow : Colors.white24, width: 2),
            boxShadow: filled ? [BoxShadow(color: _primaryYellow.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)] : [],
          ),
        );
      }),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        for (var row in [[1,2,3], [4,5,6], [7,8,9]]) 
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((num) => _buildNumKey('$num')).toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 72), // Spacer
            _buildNumKey('0'),
            _buildNumKey('back', icon: Icons.backspace_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildNumKey(String val, {IconData? icon}) {
    return InkWell(
      onTap: () => val == 'back' ? _pinBackspace() : _pinKeyPressed(val),
      borderRadius: BorderRadius.circular(40),
      hoverColor: _primaryYellow.withOpacity(0.05),
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.02),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Center(
          child: icon != null 
            ? Icon(icon, color: _primaryYellow, size: 22) 
            : Text(val, style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w500, color: Colors.white)),
        ),
      ),
    );
  }
}
