import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dashboard_page.dart';
import 'register_cafe_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // --- PALET WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _whiteSurface = const Color(0xFFF5F5F5);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  // --- FUNGSI HUBUNGI WHATSAPP (FIXED) ---
  Future<void> _contactAdmin() async {
    // Ganti nomor ini dengan nomor Admin/CS Anda
    const String phoneNumber = "6281230112240";
    const String message = "Halo Admin Kafe Sri Rahajoe, saya butuh bantuan terkait akses login aplikasi.";

    // 1. Coba buka pakai Scheme Aplikasi (Langsung ke App WA)
    final Uri appUrl = Uri.parse("whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}");

    // 2. Fallback jika App tidak terdeteksi (Buka via Browser/Universal Link)
    final Uri webUrl = Uri.parse("https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}");

    try {
      // Coba luncurkan mode App dulu
      if (await canLaunchUrl(appUrl)) {
        await launchUrl(appUrl);
      }
      // Jika gagal, coba luncurkan mode Browser (External Application)
      else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showErrorSnackBar("Tidak dapat membuka WhatsApp: $e");
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      try {
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);

        final String uid = userCredential.user!.uid;
        DatabaseReference ref = FirebaseDatabase.instance.ref("users/$uid");
        final snapshot = await ref.get();

        if (!mounted) {
          setState(() => _isLoading = false);
          return;
        }

        if (snapshot.exists) {
          Map data = snapshot.value as Map;
          String companyId = data['company_id']?.toString() ?? "";

          if (companyId.isEmpty && data['role'] != 'admin_perusahaan') {
            _showErrorSnackBar("Data kafe tidak ditemukan.");
            setState(() => _isLoading = false);
            return;
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                nama: data['nama']?.toString() ?? "User",
                role: data['role']?.toString() ?? "karyawan",
                companyId: companyId,
                email: email,
                uid: uid,
                photoUrl: data['photo_url']?.toString() ?? "",
              ),
            ),
          );
        } else {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          _showErrorSnackBar('Data user tidak ditemukan di database!');
          setState(() => _isLoading = false);
        }
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        String errorMessage = "Terjadi kesalahan";
        switch (e.code) {
          case 'user-not-found': errorMessage = "Email tidak terdaftar"; break;
          case 'wrong-password': errorMessage = "Password salah"; break;
          case 'invalid-credential': errorMessage = "Email atau password salah"; break;
          case 'user-disabled': errorMessage = "Akun dinonaktifkan"; break;
          case 'too-many-requests': errorMessage = "Terlalu banyak percobaan, coba nanti"; break;
          default: errorMessage = e.message ?? "Terjadi kesalahan";
        }
        _showErrorSnackBar(errorMessage);
        setState(() => _isLoading = false);
      } catch (e) {
        if (!mounted) return;
        _showErrorSnackBar('Error: ${e.toString()}');
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  void _showResetPasswordDialog() {
    final TextEditingController resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Reset Password", style: TextStyle(fontWeight: FontWeight.bold, color: _textBlack)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Masukkan email Anda:", style: TextStyle(color: _textGrey, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: resetEmailController,
              style: TextStyle(color: _textBlack),
              decoration: InputDecoration(
                filled: true,
                fillColor: _whiteSurface,
                hintText: 'Email',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                _showErrorSnackBar("Email tidak valid");
                return;
              }
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Link reset terkirim"), backgroundColor: Colors.green),
                );
              } catch (e) {
                _showErrorSnackBar("Error: $e");
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _elegantBlack,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Kirim"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- LOGO SECTION ---
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _whiteCard,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icon.png',
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.coffee, size: 45, color: _textBlack),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                "ABSENSI KAFE",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: _textBlack,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Sistem Manajemen Karyawan",
                style: TextStyle(fontSize: 14, color: _textGrey),
              ),
              const SizedBox(height: 40),

              // --- FORM SECTION ---
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: _whiteCard,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: _borderGrey),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailController,
                        style: TextStyle(color: _textBlack),
                        decoration: InputDecoration(
                          hintText: 'Email Address',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                          prefixIcon: Icon(Icons.email_outlined, color: _textBlack, size: 20),
                          filled: true,
                          fillColor: _whiteSurface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) => (val == null || !val.contains('@')) ? 'Email tidak valid' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        style: TextStyle(color: _textBlack),
                        decoration: InputDecoration(
                          hintText: 'Password',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                          prefixIcon: Icon(Icons.lock_outline, color: _textBlack, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textGrey, size: 20),
                            onPressed: _togglePasswordVisibility,
                          ),
                          filled: true,
                          fillColor: _whiteSurface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        obscureText: _obscurePassword,
                        validator: (val) => (val == null || val.length < 6) ? 'Min 6 karakter' : null,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _showResetPasswordDialog,
                          child: Text(
                            'Lupa Password?',
                            style: TextStyle(color: _textGrey, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _elegantBlack,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('MASUK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (c) => const RegisterCafePage()));
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: BorderSide(color: _elegantBlack, width: 1.5),
                        ),
                        child: const Text("DAFTAR KAFE BARU", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                    ],
                  ),
                ),
              ),

              // --- FOOTER ---
              const SizedBox(height: 32),
              Text("Butuh bantuan akses?", style: TextStyle(color: _textGrey, fontSize: 13)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: _contactAdmin,
                child: Text(
                  "Hubungi Administrator (WhatsApp)",
                  style: TextStyle(
                    color: _textBlack,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text("© 2026 Ivan Kafi Pradana", style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}