// File: lib/register_cafe_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class RegisterCafePage extends StatefulWidget {
  const RegisterCafePage({super.key});

  @override
  State<RegisterCafePage> createState() => _RegisterCafePageState();
}

class _RegisterCafePageState extends State<RegisterCafePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _kafeNameController = TextEditingController();
  final TextEditingController _adminNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  // --- PALET WARNA ELEGANT (SESUAI LOGIN PAGE) ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _elegantBlack = const Color(0xFF212121);

  void _registerCafe() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // 1. Buat Akun Auth Firebase
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim());

      String uid = userCredential.user!.uid;

      // 2. Generate Company ID Unik (Contoh: KAFE-20260117)
      String timestamp = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
      String companyId = "KAFE-$timestamp";

      DatabaseReference dbRef = FirebaseDatabase.instance.ref();

      // 3. Daftarkan Data Kafe ke Folder 'companies'
      await dbRef.child("companies/$companyId/info_kafe").set({
        "nama_kafe": _kafeNameController.text.trim(),
        "admin_pembuat": _adminNameController.text.trim(),
        "created_at": ServerValue.timestamp,
        "is_active": true,
      });

      // 4. Daftarkan User ini sebagai 'admin' di bawah company tersebut
      await dbRef.child("users/$uid").set({
        "uid": uid,
        "nama": _adminNameController.text.trim(),
        "email": _emailController.text.trim(),
        "role": "admin", // Pendaftar pertama otomatis jadi Admin Kafe
        "company_id": companyId,
        "created_at": ServerValue.timestamp,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pendaftaran Kafe Berhasil! Silakan Login.")),
      );
      Navigator.pop(context); // Kembali ke Login

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(title: const Text("Daftarkan Kafe Baru"), backgroundColor: _whiteCard, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildField(_kafeNameController, "Nama Kafe", Icons.coffee),
              const SizedBox(height: 16),
              _buildField(_adminNameController, "Nama Lengkap Admin", Icons.person),
              const SizedBox(height: 16),
              _buildField(_emailController, "Email Admin", Icons.email, isEmail: true),
              const SizedBox(height: 16),
              _buildField(_passwordController, "Password", Icons.lock, isPass: true),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _registerCafe,
                  style: ElevatedButton.styleFrom(backgroundColor: _elegantBlack, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("DAFTARKAN SEKARANG", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {bool isPass = false, bool isEmail = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPass,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _textBlack),
        filled: true, fillColor: _whiteCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (v) => (v == null || v.isEmpty) ? "Wajib diisi" : null,
    );
  }
}