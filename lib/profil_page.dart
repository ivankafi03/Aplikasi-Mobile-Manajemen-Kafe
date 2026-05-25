import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

final supabase = Supabase.instance.client;

class ProfilPage extends StatefulWidget {
  final String nama;
  final String email;
  final String role;
  final String uid;

  const ProfilPage({
    super.key,
    required this.nama,
    required this.email,
    required this.role,
    required this.uid,
  });

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  // --- PALET WARNA DASAR ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  String? _fotoUrl;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
  }

  // ✅ FUNGSI PENTING: MENENTUKAN WARNA BERDASARKAN ROLE
  Color _getRoleColor() {
    String role = widget.role.trim().toLowerCase();
    if (role == 'owner') return const Color(0xFF6A1B9A); // 👑 Ungu (Bos)
    if (role == 'manager') return const Color(0xFFE65100); // 👔 Oranye (Manager)
    if (role.contains('admin')) return const Color(0xFF1565C0); // 🛠 Biru (Admin)
    return const Color(0xFF2E7D32); // 👷‍♂️ Hijau (Karyawan)
  }

  void _loadProfilePhoto() {
    DatabaseReference ref = FirebaseDatabase.instance.ref("users/${widget.uid}");
    ref.child("photo_url").onValue.listen((event) {
      if (event.snapshot.exists && mounted) {
        setState(() {
          _fotoUrl = event.snapshot.value.toString();
        });
      }
    });
  }

  Future<void> _gantiFotoProfil() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 70,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      File fileGambar = File(pickedFile.path);
      String fileName = "${widget.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg";
      String path = 'avatars/$fileName';

      await supabase.storage.from('avatars').upload(
        path,
        fileGambar,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      final String publicUrl = supabase.storage.from('avatars').getPublicUrl(path);

      await FirebaseDatabase.instance.ref("users/${widget.uid}").update({
        "photo_url": publicUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("Foto profil diperbarui!"), backgroundColor: _getRoleColor()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal upload: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showChangePasswordDialog(BuildContext context) {
    final TextEditingController passController = TextEditingController();
    Color roleColor = _getRoleColor();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Ganti Password", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textBlack)),
              const SizedBox(height: 8),
              Text("Masukkan password baru untuk akun Anda.", style: TextStyle(color: _textGrey, fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: passController,
                obscureText: true,
                style: TextStyle(color: _textBlack),
                decoration: InputDecoration(
                  hintText: "Password Baru (Min 6 karakter)",
                  hintStyle: TextStyle(color: _textGrey.withValues(alpha: 0.5)),
                  prefixIcon: Icon(Icons.lock_rounded, color: roleColor),
                  filled: true,
                  fillColor: _bgScaffold,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Batal", style: TextStyle(color: _textGrey, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (passController.text.length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Password minimal 6 karakter!"), backgroundColor: Colors.red));
                          return;
                        }
                        try {
                          await FirebaseAuth.instance.currentUser?.updatePassword(passController.text);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: const Text("Password berhasil diganti!"), backgroundColor: roleColor));
                        } catch (e) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: roleColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text("Simpan"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.logout_rounded, color: Colors.red, size: 32),
              ),
              const SizedBox(height: 20),
              Text("Konfirmasi Keluar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textBlack)),
              const SizedBox(height: 8),
              Text("Anda harus login kembali untuk mengakses akun ini.", textAlign: TextAlign.center, style: TextStyle(color: _textGrey)),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textBlack,
                        side: BorderSide(color: _borderGrey, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Batal", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginPage()),
                              (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.red.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Ya, Keluar", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color roleColor = _getRoleColor(); // Dapatkan warna sesuai role

    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Profil Saya", style: TextStyle(fontWeight: FontWeight.w700, color: _textBlack, letterSpacing: 0.5)),
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 100),
        child: Column(
          children: [
            // --- 1. HERO PROFILE CARD (WARNA DINAMIS SESUAI ROLE) ---
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 50),
                  padding: const EdgeInsets.fromLTRB(20, 65, 20, 30),
                  decoration: BoxDecoration(
                    color: roleColor, // ✅ BACKGROUND BERUBAH WARNA
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(color: roleColor.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Nama User (Putih)
                      Text(
                          widget.nama,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)
                      ),
                      const SizedBox(height: 8),

                      // Badge Jabatan (Putih dengan Teks Warna Role)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white, // Badge Putih
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.role.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: roleColor, // Teks warna role
                              letterSpacing: 1.2
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Floating Avatar
                Positioned(
                  top: 0,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: roleColor.withValues(alpha: 0.3), blurRadius: 25, offset: const Offset(0, 10))],
                        ),
                        child: CircleAvatar(
                          radius: 55,
                          backgroundColor: _whiteCard,
                          child: CircleAvatar(
                            radius: 51,
                            backgroundColor: _bgScaffold,
                            backgroundImage: _fotoUrl != null && _fotoUrl!.isNotEmpty ? NetworkImage(_fotoUrl!) : null,
                            child: (_fotoUrl == null || _fotoUrl!.isEmpty)
                                ? Icon(Icons.person, size: 50, color: _textGrey.withValues(alpha: 0.5))
                                : null,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: GestureDetector(
                          onTap: _isUploading ? null : _gantiFotoProfil,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: roleColor, // ✅ Tombol Edit mengikuti warna Role
                              shape: BoxShape.circle,
                              border: Border.all(color: _whiteCard, width: 3),
                              boxShadow: [BoxShadow(color: roleColor.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 4))],
                            ),
                            child: _isUploading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // --- 2. MENU DENGAN IKON WARNA SESUAI ROLE ---
            Container(
              decoration: BoxDecoration(
                color: _whiteCard,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  _buildListTile(
                    icon: Icons.email_rounded,
                    color: roleColor, // Icon mengikuti warna role
                    title: "Alamat Email",
                    subtitle: widget.email,
                    showArrow: false,
                  ),
                  _buildDivider(),
                  _buildListTile(
                    icon: Icons.lock_outline_rounded,
                    color: Colors.orange, // Icon Keamanan tetap Oranye (Standard)
                    title: "Keamanan Akun",
                    subtitle: "Ubah kata sandi anda",
                    onTap: () => _showChangePasswordDialog(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // --- 3. LOGOUT BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 56,
              child: TextButton(
                onPressed: () => _showLogoutDialog(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.08),
                  foregroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 10),
                    Text("Keluar Aplikasi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            Text("Versi 1.0.0 • Kafe Management", style: TextStyle(color: _textGrey.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    bool showArrow = true,
    VoidCallback? onTap
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Icon dengan Background Warna Transparan
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _textBlack)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: _textGrey)),
                  ],
                ),
              ),
              if (showArrow)
                Icon(Icons.arrow_forward_ios_rounded, color: _textGrey.withValues(alpha: 0.5), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, color: _borderGrey, indent: 76);
  }
}