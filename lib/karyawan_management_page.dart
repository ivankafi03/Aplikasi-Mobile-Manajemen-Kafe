import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class KaryawanManagementPage extends StatefulWidget {
  final String companyId;
  final String myRole;

  const KaryawanManagementPage({
    super.key,
    required this.companyId,
    required this.myRole,
  });

  @override
  State<KaryawanManagementPage> createState() => _KaryawanManagementPageState();
}

class _KaryawanManagementPageState extends State<KaryawanManagementPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref("users");
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _posisiController = TextEditingController();

  String _searchQuery = "";
  String _selectedRole = 'karyawan';
  String _editingUserId = "";
  bool _isLoading = false;

  // --- PALET WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  @override
  void dispose() {
    _searchController.dispose();
    _namaController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _posisiController.dispose();
    super.dispose();
  }

  Stream<DatabaseEvent> _getKaryawanStream() {
    return _dbRef
        .orderByChild("company_id")
        .equalTo(widget.companyId)
        .onValue;
  }

  // ✅ LOGIKA WARNA JABATAN
  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner': return const Color(0xFF6A1B9A); // 👑 Ungu
      case 'manager': return const Color(0xFFE65100); // 👔 Oranye
      case 'admin':
      case 'admin_perusahaan': return const Color(0xFF1565C0); // 🛠 Biru
      default: return const Color(0xFF2E7D32); // 👷‍♂️ Hijau (Karyawan)
    }
  }

  List<String> _getAvailableRoles() {
    String role = widget.myRole.toLowerCase();
    if (role == 'admin' || role == 'admin_perusahaan') return ['owner', 'manager', 'karyawan'];
    if (role == 'owner') return ['manager', 'karyawan'];
    return ['karyawan'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Tim & Karyawan", style: TextStyle(fontWeight: FontWeight.w600, color: _textBlack)),
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: _textBlack),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: _borderGrey, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder(
              stream: _getKaryawanStream(),
              builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  Map data = snapshot.data!.snapshot.value as Map;
                  List<Map<String, dynamic>> items = [];

                  data.forEach((key, value) {
                    if (key != _auth.currentUser?.uid) {
                      items.add({'uid': key, ...Map<String, dynamic>.from(value)});
                    }
                  });

                  items.sort((a, b) => (a['nama'] ?? '').toString().compareTo(b['nama'] ?? ''));
                  final filtered = items.where((k) =>
                      k['nama'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
                  ).toList();

                  if (filtered.isEmpty) return _buildEmptyState("Karyawan tidak ditemukan");

                  // Grouping berdasarkan Role
                  final Map<String, List<Map<String, dynamic>>> cat = {
                    'owner': filtered.where((e) => e['role'] == 'owner').toList(),
                    'manager': filtered.where((e) => e['role'] == 'manager').toList(),
                    'admin': filtered.where((e) => e['role'].toString().contains('admin')).toList(),
                    'karyawan': filtered.where((e) => e['role'] == 'karyawan').toList(),
                  };

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    children: [
                      if (cat['owner']!.isNotEmpty) ...[_buildSectionHeader("OWNER", _getRoleColor('owner')), ...cat['owner']!.map((k) => _buildUserCard(k))],
                      if (cat['manager']!.isNotEmpty) ...[_buildSectionHeader("MANAGER", _getRoleColor('manager')), ...cat['manager']!.map((k) => _buildUserCard(k))],
                      if (cat['admin']!.isNotEmpty) ...[_buildSectionHeader("ADMINISTRATOR", _getRoleColor('admin')), ...cat['admin']!.map((k) => _buildUserCard(k))],
                      if (cat['karyawan']!.isNotEmpty) ...[_buildSectionHeader("STAFF & KARYAWAN", _getRoleColor('karyawan')), ...cat['karyawan']!.map((k) => _buildUserCard(k))],
                      const SizedBox(height: 100),
                    ],
                  );
                }
                return _buildEmptyState("Belum ada karyawan terdaftar");
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFormDialog(),
        label: const Text("Tambah Anggota", style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.person_add_rounded),
        backgroundColor: _elegantBlack,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _whiteCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: "Cari nama atau email...",
          hintStyle: TextStyle(color: _textGrey.withValues(alpha: 0.5)),
          prefixIcon: Icon(Icons.search_rounded, color: _textGrey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10, left: 8),
      child: Row(
        children: [
          // Indikator Warna Kecil
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, letterSpacing: 1.2)),
        ],
      ),
    );
  }

  // ✅ CARD KARYAWAN (FULL COLOR / SOLID)
  Widget _buildUserCard(Map<String, dynamic> k) {
    final roleColor = _getRoleColor(k['role']);
    final initial = (k['nama'] ?? "?")[0].toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: roleColor, // ✅ Background Full Warna
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: roleColor.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Avatar Background Putih (Kontras)
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white,
          child: Text(initial, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        // Teks Putih
        title: Text(k['nama'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.work_outline_rounded, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                const SizedBox(width: 4),
                Text("${k['posisi'] ?? 'Staf'}", style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
            const SizedBox(height: 8),
            // Badge Jabatan Transparan
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                k['role'].toString().toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            )
          ],
        ),
        trailing: _buildMoreMenu(k),
      ),
    );
  }

  Widget? _buildMoreMenu(Map<String, dynamic> k) {
    String targetRole = k['role'].toString().toLowerCase();
    String myRole = widget.myRole.toLowerCase();

    bool canEdit = true;
    if (myRole == 'manager' && (targetRole == 'owner' || targetRole == 'admin' || targetRole == 'admin_perusahaan')) {
      canEdit = false;
    }

    if (!canEdit) return null;

    // Icon Menu Putih karena background berwarna
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      color: _whiteCard,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (val) {
        if (val == 'edit') _showFormDialog(isEdit: true, karyawanData: k);
        if (val == 'del') _hapusKaryawan(k['uid'], k['nama']);
      },
      itemBuilder: (c) => [
        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 18), SizedBox(width: 8), Text("Edit Data")])),
        const PopupMenuItem(value: 'del', child: Row(children: [Icon(Icons.delete_rounded, size: 18, color: Colors.red), SizedBox(width: 8), Text("Hapus", style: TextStyle(color: Colors.red))])),
      ],
    );
  }

  void _showFormDialog({bool isEdit = false, Map<String, dynamic>? karyawanData}) {
    List<String> roles = _getAvailableRoles();
    if (isEdit && karyawanData != null) {
      _namaController.text = karyawanData['nama'] ?? '';
      _posisiController.text = karyawanData['posisi'] ?? '';
      _selectedRole = karyawanData['role'];
      _editingUserId = karyawanData['uid'];
    } else {
      _clearForm();
      if (roles.isNotEmpty) _selectedRole = roles.last;
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _whiteCard,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(isEdit ? "Edit Anggota" : "Tambah Anggota", style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField(_namaController, "Nama Lengkap", Icons.person_outline),
                if (!isEdit) ...[
                  const SizedBox(height: 16),
                  _buildField(_emailController, "Alamat Email", Icons.email_outlined),
                  const SizedBox(height: 16),
                  _buildField(_passwordController, "Password", Icons.lock_outline, obs: true),
                ],
                const SizedBox(height: 16),
                _buildField(_posisiController, "Posisi / Jabatan", Icons.work_outline),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _bgScaffold,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderGrey),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRole,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: roles.map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))
                      )).toList(),
                      onChanged: (v) => setDialogState(() => _selectedRole = v!),
                    ),
                  ),
                )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Batal", style: TextStyle(color: _textGrey))
            ),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _elegantBlack,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: _isLoading ? null : (isEdit ? _editKaryawan : _tambahKaryawan),
                child: Text(isEdit ? "Simpan Perubahan" : "Tambah")
            )
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController c, String l, IconData i, {bool obs = false}) {
    return TextField(
        controller: c,
        obscureText: obs,
        style: TextStyle(color: _textBlack),
        decoration: InputDecoration(
            labelText: l,
            labelStyle: TextStyle(color: _textGrey),
            prefixIcon: Icon(i, color: _textGrey, size: 20),
            filled: true,
            fillColor: _bgScaffold,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
        )
    );
  }

  // --- LOGIC ---

  Future<void> _tambahKaryawan() async {
    if (_namaController.text.isEmpty || _emailController.text.isEmpty) return;
    setState(() => _isLoading = true);

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );

      UserCredential userCredential = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim()
      );

      await _dbRef.child(userCredential.user!.uid).set({
        "uid": userCredential.user!.uid,
        "nama": _namaController.text.trim(),
        "email": _emailController.text.trim(),
        "role": _selectedRole,
        "posisi": _posisiController.text.trim(),
        "company_id": widget.companyId,
        "is_active": true,
        "created_at": ServerValue.timestamp,
        "photo_url": "",
      });

      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar("Berhasil menambah karyawan: ${_namaController.text}", Colors.green);

    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Gagal: $e", Colors.red);
    } finally {
      await secondaryApp?.delete();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editKaryawan() async {
    try {
      await _dbRef.child(_editingUserId).update({
        "nama": _namaController.text.trim(),
        "role": _selectedRole,
        "posisi": _posisiController.text.trim(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar("Data berhasil diperbarui", Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Gagal: $e", Colors.red);
    }
  }

  void _hapusKaryawan(String uid, String nama) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Hapus Akun?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("Yakin ingin menghapus $nama? User tidak akan bisa login lagi."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Batal", style: TextStyle(color: _textGrey))),
          TextButton(onPressed: () async {
            await _dbRef.child(uid).remove();
            if (!mounted) return;
            Navigator.pop(context);
            _showSnackBar("Akun dihapus", Colors.red);
          }, child: const Text("Hapus", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.groups_3_outlined, size: 60, color: _textGrey.withValues(alpha: 0.3)),
      const SizedBox(height: 16),
      Text(msg, style: TextStyle(color: _textGrey)),
    ],
  ));

  void _showSnackBar(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg, behavior: SnackBarBehavior.floating));
  }

  void _clearForm() {
    _namaController.clear(); _emailController.clear();
    _passwordController.clear(); _posisiController.clear();
  }
}