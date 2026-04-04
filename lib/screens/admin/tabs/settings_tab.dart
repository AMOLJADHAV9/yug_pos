import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _gstPercentCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gstNumberCtrl = TextEditingController(); // Added GST Number
  bool _loading = false;
  bool _saving = false;

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
        _gstPercentCtrl.text = (data['gstPercentage'] ?? 0).toString();
        _addressCtrl.text = (data['address'] ?? '').toString();
        _gstNumberCtrl.text = (data['gstNumber'] ?? '').toString();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _saveSettings() async {
    final auth = context.read<AuthService>();
    final restaurantId = auth.restaurantId;
    if (restaurantId == null) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('restaurants').doc(restaurantId).set({
        'gstPercentage': double.tryParse(_gstPercentCtrl.text) ?? 0,
        'address': _addressCtrl.text.trim(),
        'gstNumber': _gstNumberCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (auth.restaurantName != null) 'name': auth.restaurantName,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Settings saved successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving settings: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFCDD22)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Restaurant Settings", 
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 32),
          
          _buildSectionHeader("Tax Configuration", Icons.receipt_long, Colors.blue),
          const SizedBox(height: 24),

          Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF141615),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("RESTAURANT ADDRESS", 
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                TextField(
                  controller: _addressCtrl,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: "Enter Full Address",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                const Text("GST NUMBER (GSTIN)", 
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                TextField(
                  controller: _gstNumberCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter GST Number",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                const Text("GST PERCENTAGE (%)", 
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                TextField(
                  controller: _gstPercentCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter GST % (e.g. 5, 12, 18)",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixText: "%",
                    suffixStyle: const TextStyle(color: Color(0xFFFCDD22), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFCDD22),
                      foregroundColor: const Color(0xFF141615),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF141615)))
                      : const Text("SAVE SETTINGS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
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
          decoration: BoxDecoration(color: const Color(0xFFFCDD22).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: const Color(0xFFFCDD22), size: 18),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1)),
      ],
    );
  }
}
