import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../../../services/auth_service.dart';
import '../bluetooth_printer_settings_screen.dart';
import '../../../services/bluetooth_printer_service.dart';
import 'dart:io';
import '../../../utils/navigator_utils.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  // Data variables
  String? _restaurantName;
  String? _address;
  String? _gstNumber;
  String? _gstPercent;
  String? _selectedState;
  String? _terms;
  String? _privacy;
  String? _refund;
  String? _help;
  
  bool _loading = false;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  void _fetchSettings() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId != null) {
      final doc = await FirebaseFirestore.instance.collection('restaurants').doc(restaurantId).get();
      if (doc.exists) {
        final data = doc.data()!;
        _restaurantName = (data['name'] ?? auth.restaurantName ?? 'Not Set').toString();
        _address = (data['address'] ?? 'Not Set').toString();
        _gstNumber = (data['gstNumber'] ?? 'Not Set').toString();
        _gstPercent = (data['gstPercentage'] ?? 0).toString();
        _selectedState = data['state'] ?? 'Not Set';
        _terms = (data['termsAndConditions'] ?? 'Not Set').toString();
        _privacy = (data['privacyPolicy'] ?? 'Not Set').toString();
        _refund = (data['refundPolicy'] ?? 'Not Set').toString();
        _help = (data['helpSupport'] ?? 'Not Set').toString();
      } else {
        _restaurantName = auth.restaurantName ?? 'Not Set';
        _address = 'Not Set';
        _gstNumber = 'Not Set';
        _gstPercent = '0';
        _selectedState = 'Not Set';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // --- Official Text Fallbacks ---
  static const String _officialTermsFallback = """TERMS AND CONDITIONS OF USE
Effective Date: April 7, 2026
Version 1.0

Please read these Terms and Conditions ("Terms") carefully before using the Yug POS application ("Application", "Software", or "ldma_pos"). By installing, accessing, or operating this Application, you ("User", "Licensee", or "Operator") agree to be bound by these Terms. If you do not agree, do not install or use the Application.

1. Definitions
• "Application" means the Yug POS Flutter-based restaurant management software, including all its modules: Admin Dashboard, Cashier Counter, and Waiter Interface.
• "Operator" means the restaurant, food-service business, or individual who has deployed and configured the Application on their premises.
• "Staff User" means any person (Admin, Cashier, or Waiter) granted login credentials to access the Application.
• "Transaction Data" means any order, billing, settlement, KOT (Kitchen Order Ticket), refund, or report generated through the Application.
• "Firebase Services" means Google Firebase (Authentication, Cloud Firestore, Firebase Storage) used as the backend for the Application.
• "GST" means Goods and Services Tax as applicable under Indian taxation law.

2. License Grant
2.1 Grant of Use
Subject to compliance with these Terms, the Operator is granted a non-exclusive, non-transferable, revocable license to install and use the Application solely for their internal restaurant management operations.
2.2 Restrictions
The Operator shall not:
• Resell, sublicense, lease, or redistribute the Application or its source code to any third party.
• Reverse-engineer, decompile, disassemble, or attempt to derive the source code of the Application except to the extent permitted by applicable law.
• Modify or create derivative works of the Application without prior written consent.
• Remove or alter any proprietary notices, trademarks, or branding within the Application.

3. User Roles and Access Control
3.1 Role-Based Access
The Application operates under three distinct user roles:
• Admin: Full access to revenue dashboards, analytics, menu management, staff management, table configuration, category sales reports, KOT management, billing history.
• Cashier: Billing occupied tables, takeaway/delivery orders, online orders (Zomato, Swiggy, Uber Eats), daily reports, temporary tables, order history, cancellations, and refunds.
• Waiter: Restricted access to place orders and generate KOTs for kitchen communication only.

4. Data Ownership, Storage and Privacy
4.1 Data Ownership
All Transaction Data remains the property of the Operator.
4.2 Cloud Storage
Utilises Google Firebase (Cloud Firestore and Firebase Storage). By using the Application, the Operator acknowledges Google Firebase's Terms of Service.
4.4 Personal Data
Operator is responsible for complying with applicable data protection laws of India, including the Digital Personal Data Protection Act, 2023.

5. Billing, Receipts and GST Compliance
The Operator is responsible for ensuring accurately configured restaurant name, address, and GSTIN. Developers are not liable for tax shortfall or penalties arising from incorrect configuration.

6. Printing and Hardware Integration
Supports Bluetooth thermal printers, USB thermal printers (ESC/POS protocol), and PDF. Operator is responsible for hardware procurement and maintenance.

7. Third-Party Online Order Integrations
Facilitates management of Zomato, Swiggy, and Uber Eats orders but does not form contractual relationships between Developer and platforms.

8. Order Cancellations and Refunds
Cashier role authorized to cancel orders and process refunds. All cancellations are logged for audit.

9. Reports and Analytics
Operator responsible for verifying accuracy of generated reports before financial or tax filings.

10. Intellectual Property
All intellectual property rights in the Application remain the exclusive property of the Developer.

11. Disclaimer of Warranties
THE APPLICATION IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND.

12. Limitation of Liability
Developer's total cumulative liability shall not exceed the amount paid (if any) by the Operator in the preceding twelve months.

13. Updates and Modifications
Developer may release updates or modify these Terms at any time.

14. Termination
License remains effective until terminated by Operator (uninstallation) or Developer (material breach).

15. Governing Law
Governed by laws of India. Disputes subject to exclusive jurisdiction of competent courts in Maharashtra, India.

16. General Provisions
Entire Agreement, Severability, Waiver, and Assignment clauses as per standard software licensing.

17. Acknowledgement
By using Yug POS, you confirm you have read, understood, and agree to be bound by these Terms.""";

  static const String _privacyPolicyFallback = """YUG POS – PRIVACY POLICY
Effective Date: April 7, 2026

1. Introduction
This Privacy Policy describes how YUG POS collects, uses, and protects information when you use the Application.

2. Information Collection
We may collect business details, user credentials, transaction data, and technical information such as device logs and usage data.

3. Use of Information
Information is used to operate the Application, generate reports, improve services, and provide support. We do not sell user data.

4. Data Storage
Data is stored securely using cloud services such as Google Firebase. By using the Application, you agree to third-party service policies.

5. Data Security
We implement reasonable security measures. However, users are responsible for protecting their credentials and ensuring secure usage.

6. Data Ownership
All business data belongs to the Operator. YUG POS does not claim ownership of user-generated data.

7. Data Sharing
Data is not shared except where required by law or necessary for service functionality.

8. Legal Compliance
Operators handling personal data must comply with the Digital Personal Data Protection Act, 2023.

9. Data Retention and Deletion
Data is retained while accounts are active and may be deleted after termination. Users should maintain backups.

10. Policy Updates
This Privacy Policy may be updated periodically. Continued use indicates acceptance.""";

  static const String _refundPolicyFallback = """YUG POS – REFUND POLICY
Effective Date: April 7, 2026

1. Introduction
This Refund Policy applies to all payments made for YUG POS services and subscriptions.

2. Subscription Fees
All subscription fees must be paid in advance. Payments grant access to services for the selected period.

3. No Refund Policy
All payments are non-refundable unless explicitly stated otherwise. No refunds will be issued for unused subscription periods.

4. Exceptions
Refunds may be considered in cases such as duplicate payments, technical failures, or non-activation of services. Approval is at the sole discretion of the Developer.

5. Cancellation
Users may cancel their subscription at any time. Access will continue until the end of the billing cycle. No refunds will be provided after cancellation.

6. Misuse
No refunds will be granted in cases of misuse, fraud, or violation of Terms.

7. Refund Processing
Approved refunds will be processed within 7–30 business days through the original payment method.

8. Limitation of Liability
Refund liability shall not exceed the amount paid by the user.""";

  static const String _helpSupportFallback = """CUSTOMER SUPPORT

YUG POS is committed to providing reliable support services. If you require assistance regarding billing, technical issues, or general inquiries, please reach out to us:

PHONE: +91 9876543210
EMAIL: support@yugpos.com
WEBSITE: www.yugpos.com

We strive to respond to all support requests within 24–48 business hours. Response times may vary depending on the complexity of the issue.""";

  // --- Functions ---
  
  Future<void> _updateOfficialLegal() async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;

    setState(() => _updating = true);

    try {
      await FirebaseFirestore.instance.collection('restaurants').doc(restaurantId).set({
        'termsAndConditions': _officialTermsFallback,
        'privacyPolicy': _privacyPolicyFallback,
        'refundPolicy': _refundPolicyFallback,
        'helpSupport': _helpSupportFallback,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      _fetchSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All legal documents updated successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Update failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _showPremiumLegalCenter(String title, String? content, String fallback) {
    String effectiveContent = (content == null || content == 'Not Set' || content.isEmpty) 
        ? fallback 
        : content;
    
    final isSupport = title.contains("Help");
    final themeColor = isSupport ? Colors.blue : const Color(0xFFFCDD22);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _LegalCenterOverlay(
        title: title, 
        content: effectiveContent, 
        themeColor: themeColor,
        isSupport: isSupport,
        restaurantName: _restaurantName ?? "THE OPERATOR",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)));
    }

    final auth = context.watch<AuthService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserProfileHeader(auth),
          const SizedBox(height: 40),
          
          _buildSectionHeader("Business Identity", Icons.store_rounded, Colors.blue),
          const SizedBox(height: 16),
          _buildInfoGroup([
            _buildInfoTile(Icons.restaurant_rounded, "RESTAURANT NAME", _restaurantName),
            _buildInfoTile(Icons.location_on_rounded, "ADDRESS", _address),
            _buildInfoTile(Icons.map_rounded, "STATE", _selectedState),
          ]),

          const SizedBox(height: 32),
          _buildSectionHeader("Tax Configuration", Icons.receipt_long, Colors.green),
          const SizedBox(height: 16),
          _buildInfoGroup([
            _buildInfoTile(Icons.tag_rounded, "GST NUMBER (GSTIN)", _gstNumber),
            _buildInfoTile(Icons.percent_rounded, "GST PERCENTAGE", "${_gstPercent}%"),
          ]),

          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildSectionHeader("Legal & Support", Icons.gavel_rounded, Colors.purple)),
              TextButton.icon(
                onPressed: _updating ? null : _updateOfficialLegal,
                icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFFFCDD22)),
                label: Text((_terms == 'Not Set' || _privacy == 'Not Set' || _help == 'Not Set') ? "INITIALIZE" : "RESET LEGAL", 
                  style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoGroup([
            _buildInfoTile(
              Icons.description_rounded, 
              "TERMS AND CONDITIONS", 
              _terms == 'Not Set' ? "Click to view standard terms" : _terms, 
              onTap: () => _showPremiumLegalCenter("Terms and Conditions", _terms, _officialTermsFallback),
              isClickable: true,
            ),
            _buildInfoTile(
              Icons.privacy_tip_rounded, 
              "PRIVACY POLICY", 
              _privacy == 'Not Set' ? "Click to view standard policy" : _privacy,
              onTap: () => _showPremiumLegalCenter("Privacy Policy", _privacy, _privacyPolicyFallback),
              isClickable: true,
            ),
            _buildInfoTile(
              Icons.monetization_on_rounded, 
              "REFUND POLICY", 
              _refund == 'Not Set' ? "Click to view standard policy" : _refund,
              onTap: () => _showPremiumLegalCenter("Refund Policy", _refund, _refundPolicyFallback),
              isClickable: true,
            ),
            _buildInfoTile(
              Icons.help_outline_rounded, 
              "HELP AND SUPPORT", 
              _help == 'Not Set' ? "Click to view support details" : _help,
              onTap: () => _showPremiumLegalCenter("Help and Support", _help, _helpSupportFallback),
              isClickable: true,
            ),
          ]),

          const SizedBox(height: 40),
          _buildPrinterSection(context),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildUserProfileHeader(AuthService auth) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: const Color(0xFFFCDD22).withOpacity(0.1),
            child: const Icon(Icons.person_rounded, size: 40, color: Color(0xFFFCDD22)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(auth.userName ?? "User", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(auth.role.name.toUpperCase(), style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(auth.currentUser?.email ?? "No Email", style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(title, 
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: Colors.white.withOpacity(0.05), thickness: 1)),
      ],
    );
  }

  Widget _buildInfoGroup(List<Widget> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141615),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(children: tiles),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String? value, {VoidCallback? onTap, bool isClickable = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.03), width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isClickable ? const Color(0xFFFCDD22).withOpacity(0.5) : Colors.white24, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Color(0xFFFCDD22), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    (value == null || value.isEmpty) ? "Not Set" : value, 
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                    maxLines: isClickable ? 2 : 10,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isClickable && value != null && value.length > 50)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text("VIEW FULL DOCUMENT", style: TextStyle(color: Color(0xFFFCDD22), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            if (isClickable)
              const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterSection(BuildContext context) {
    if (Platform.isWindows) return const SizedBox.shrink();

    final printerService = context.watch<BluetoothPrinterService>();
    final isConnected = printerService.isConnected;
    final printerName = printerService.selectedDevice?.name ?? "No Printer Connected";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Hardware & Printing", Icons.print_rounded, Colors.orange),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF141615),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: (isConnected ? Colors.green : Colors.red).withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: isConnected ? Colors.green : Colors.red, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(printerName.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(isConnected ? "Active & Ready" : "Disconnected", style: TextStyle(color: isConnected ? Colors.green : Colors.red, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BluetoothPrinterSettingsScreen())),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFCDD22),
                    side: const BorderSide(color: Color(0xFFFCDD22)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("CONFIGURE PRINTER", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Premium Overlay Component ---

class _LegalCenterOverlay extends StatelessWidget {
  final String title;
  final String content;
  final Color themeColor;
  final bool isSupport;
  final String restaurantName;

  const _LegalCenterOverlay({
    required this.title,
    required this.content,
    required this.themeColor,
    required this.isSupport,
    required this.restaurantName,
  });

  @override
  Widget build(BuildContext context) {
    // Parse content into sections
    final List<_LegalSection> sections = _parseContent(content);

    return Dialog.fullscreen(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1110), Color(0xFF141615), Color(0xFF050505)],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildSliverHeader(context),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (isSupport) _buildSupportHub() else ...sections.map((s) => _buildSectionCard(s)),
                    const SizedBox(height: 48),
                    _buildAgreementSeal(),
                    const SizedBox(height: 100),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverHeader(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () => safePop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Text(
          title.toUpperCase(), 
          style: TextStyle(
            color: themeColor, 
            fontSize: 16, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 2,
            shadows: [Shadow(color: themeColor.withOpacity(0.5), blurRadius: 10)]
          ),
        ),
        background: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.1,
                child: Icon(
                  isSupport ? Icons.headset_mic_rounded : Icons.gavel_rounded,
                  size: 200,
                  color: themeColor,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(_LegalSection section) {
    final hasNumber = RegExp(r'^\d+\.').hasMatch(section.title);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_getIconForSection(section.title), color: themeColor, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        section.title,
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  section.body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.6,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupportHub() {
    return Column(
      children: [
        // Intro Text
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: themeColor.withOpacity(0.1)),
          ),
          child: const Text(
            "YUG POS is committed to providing elite support. Our response team is available 24/7 for technical emergencies.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, height: 1.5),
          ),
        ),
        const SizedBox(height: 32),
        // Action Hub
        _buildSupportTile(Icons.phone_in_talk_rounded, "Call Support", "+91 9876543210"),
        _buildSupportTile(Icons.email_rounded, "Email Assistant", "support@yugpos.com"),
        _buildSupportTile(Icons.public_rounded, "Official Website", "www.yugpos.com"),
        const SizedBox(height: 32),
        // Respond Time Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.timer_outlined, color: Colors.blue, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  "Avg Response Time: 24 - 48 Hours",
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSupportTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {}, // Future integration: launchUrl
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.blue, size: 24),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Icon(Icons.arrow_outward_rounded, color: themeColor.withOpacity(0.3), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgreementSeal() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.05),
            shape: BoxShape.circle,
            border: Border.all(color: themeColor.withOpacity(0.2), width: 2),
          ),
          child: Icon(isSupport ? Icons.verified_user_rounded : Icons.verified_rounded, color: themeColor, size: 48),
        ),
        const SizedBox(height: 24),
        Text(
          isSupport ? "OFFICIAL SUPPORT DESK" : "DYNAMIC DIGITAL SIGNATURE",
          style: TextStyle(color: themeColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            isSupport 
              ? "This support dashboard is exclusively available to active restaurant operators of the Yug POS network."
              : "By operating this terminal, \"$restaurantName\" formally confirms agreement with the $title stated above.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isSupport ? "STATUS: OPERATIONAL" : "STATUS: LEGALLY BINDING",
          style: TextStyle(color: isSupport ? Colors.white24 : Colors.green.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // --- Helpers ---

  IconData _getIconForSection(String title) {
    title = title.toLowerCase();
    if (title.contains("definition")) return Icons.book_rounded;
    if (title.contains("license")) return Icons.vpn_key_rounded;
    if (title.contains("data") || title.contains("privacy")) return Icons.security_rounded;
    if (title.contains("billing") || title.contains("gst")) return Icons.receipt_rounded;
    if (title.contains("print")) return Icons.print_rounded;
    if (title.contains("role")) return Icons.people_rounded;
    if (title.contains("refund") || title.contains("money")) return Icons.monetization_on_rounded;
    if (title.contains("cancel")) return Icons.cancel_rounded;
    if (title.contains("update") || title.contains("modify")) return Icons.update_rounded;
    if (title.contains("govern") || title.contains("law")) return Icons.gavel_rounded;
    return Icons.info_outline_rounded;
  }

  List<_LegalSection> _parseContent(String content) {
    // Split by major sections (e.g., "1. Definitions", "2. License")
    // This is a simple parser looking for digits followed by a dot
    final List<_LegalSection> sections = [];
    final lines = content.split('\n');
    
    String currentTitle = "General Overview";
    String currentBody = "";
    
    for (var line in lines) {
      if (RegExp(r'^\d+\.').hasMatch(line.trim())) {
        if (currentBody.isNotEmpty) {
          sections.add(_LegalSection(currentTitle, currentBody.trim()));
        }
        currentTitle = line.trim();
        currentBody = "";
      } else {
        currentBody += "$line\n";
      }
    }
    
    if (currentBody.isNotEmpty) {
      sections.add(_LegalSection(currentTitle, currentBody.trim()));
    }
    
    return sections;
  }
}

class _LegalSection {
  final String title;
  final String body;
  _LegalSection(this.title, this.body);
}
