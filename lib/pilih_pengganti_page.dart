import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class PilihPenggantiPage extends StatefulWidget {
  final String companyId;
  final String namaYangIzin;
  final String emailYangIzin;
  final String tanggalIzin;
  final String? izinKey;

  const PilihPenggantiPage({
    required this.companyId,
    super.key,
    required this.namaYangIzin,
    required this.emailYangIzin,
    required this.tanggalIzin,
    this.izinKey,
  });

  @override
  State<PilihPenggantiPage> createState() => _PilihPenggantiPageState();
}

class _PilihPenggantiPageState extends State<PilihPenggantiPage> {
  // --- PALET WARNA (WHITE ELEGANT THEME) ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _borderGrey = const Color(0xFFEEEEEE);
  final Color _elegantBlack = const Color(0xFF212121);

  bool _isProcessing = false;

  // ==========================================
  // LOGIKA UTAMA: SET PENGGANTI
  // ==========================================
  void _setPengganti(BuildContext context, Map dataKaryawan) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      String? targetUid = dataKaryawan['uid'];
      if (targetUid == null || targetUid.isEmpty) {
        _showSnackBar("UID Karyawan tidak ditemukan!", isError: true);
        return;
      }

      // 1. Kirim Perintah Suara ke HP Pengganti
      await FirebaseDatabase.instance.ref("companies/${widget.companyId}/notif_suara/$targetUid").set({
        "perintah": "BUNYI",
        "keterangan": "Tugas menggantikan ${widget.namaYangIzin}",
        "tanggal": widget.tanggalIzin,
        "timestamp": ServerValue.timestamp,
      });

      // 2. Simpan Perubahan Jadwal di Database
      await _simpanPengganti(
        dataKaryawan['email'] ?? '',
        dataKaryawan['nama'] ?? 'Karyawan',
      );

      if (!mounted) return;
      _showSnackBar("Berhasil menugaskan ${dataKaryawan['nama']}!");

      // Kembali ke halaman sebelumnya
      if (!context.mounted) return;

    } catch (e) {
      debugPrint("❌ GAGAL: $e");
      _showSnackBar("Terjadi kesalahan sistem", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _simpanPengganti(String emailPengganti, String namaPengganti) async {
    final ref = FirebaseDatabase.instance.ref("companies/${widget.companyId}");
    String tgl = widget.tanggalIzin;

    // --- 1. CARI & AMBIL DATA SHIFT ASLI ---
    String jamMulai = "08:00";
    String jamSelesai = "16:00";
    String shiftName = "Pagi";
    String? keyShiftLama;

    final shiftSnap = await ref.child("shifts").get();
    if (shiftSnap.exists) {
      Map dataShifts = shiftSnap.value as Map;
      dataShifts.forEach((key, value) {
        if (value['nama_karyawan'] == widget.namaYangIzin && value['tanggal'] == tgl) {
          jamMulai = value['jam_mulai'] ?? "08:00";
          jamSelesai = value['jam_selesai'] ?? "16:00";
          shiftName = value['nama_shift'] ?? "Pagi";
          keyShiftLama = key;
        }
      });
    }

    // --- 2. HAPUS SHIFT LAMA (KARYAWAN YANG IZIN) ---
    if (keyShiftLama != null) {
      await ref.child("shifts/$keyShiftLama").remove();
    }

    // --- 3. BUAT SHIFT BARU (UNTUK PENGGANTI) ---
    String emailEnc = emailPengganti.replaceAll('.', '_').replaceAll('@', '_');
    String newKey = "${emailEnc}_$tgl";
    await ref.child("shifts/$newKey").set({
      "email": emailPengganti,
      "nama_karyawan": namaPengganti,
      "tanggal": tgl,
      "jam_mulai": jamMulai,
      "jam_selesai": jamSelesai,
      "nama_shift": shiftName,
      "jenis": "penggantian",
      "keterangan": "Menggantikan ${widget.namaYangIzin}",
      "created_at": ServerValue.timestamp,
      "id_izin": widget.izinKey,
    });

    // --- 4. UPDATE DATA IZIN ---
    if (widget.izinKey != null) {
      await ref.child("izin_karyawan/${widget.izinKey}").update({
        "processed": true,
        "status": "approved",
        "pengganti_nama": namaPengganti,
        "processed_at": ServerValue.timestamp,
      });
    }

    // --- 5. CATAT RIWAYAT PENGGANTIAN (LOG) ---
    await ref.child("riwayat_penggantian").push().set({
      'nama_asli': widget.namaYangIzin,
      'nama_pengganti': namaPengganti,
      'tanggal': tgl,
      'jam_kerja': "$jamMulai - $jamSelesai",
      'waktu_proses': ServerValue.timestamp,
    });
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[800] : _elegantBlack,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Tugaskan Pengganti", style: TextStyle(fontWeight: FontWeight.w600, color: _textBlack)),
        centerTitle: true,
        backgroundColor: _whiteCard,
        elevation: 0,
        iconTheme: IconThemeData(color: _textBlack),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: _borderGrey, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          _buildHeaderInfo(),
          _buildInfoNote(),
          const SizedBox(height: 20),
          Expanded(child: _buildKaryawanList()),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _whiteCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: Colors.orange[50], child: const Icon(Icons.person_remove, color: Colors.orange)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Pengganti untuk:", style: TextStyle(fontSize: 12, color: _textGrey)),
                Text(widget.namaYangIzin, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textBlack)),
                Text("📅 ${widget.tanggalIzin}", style: TextStyle(fontSize: 12, color: _textBlack)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoNote() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 20),
          SizedBox(width: 12),
          Expanded(child: Text("Karyawan terpilih akan menerima notifikasi & suara dering otomatis.", style: TextStyle(fontSize: 11, color: Colors.blueGrey))),
        ],
      ),
    );
  }

  Widget _buildKaryawanList() {
    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref("users").onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: Text("Tidak ada data"));

        final users = snapshot.data!.snapshot.value as Map;
        final listKaryawan = [];
        users.forEach((key, val) {
          if (val['role'] == 'karyawan' && val['nama'] != widget.namaYangIzin) {
            val['uid'] = key;
            listKaryawan.add(val);
          }
        });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: listKaryawan.length,
          itemBuilder: (context, i) {
            final item = listKaryawan[i];
            bool hasToken = item['fcm_token'] != null; // Sesuaikan kunci ini dengan dashboard

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _whiteCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderGrey),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _bgScaffold,
                  child: Icon(Icons.person, color: hasToken ? _elegantBlack : _textGrey),
                ),
                title: Text(item['nama'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(item['posisi'] ?? "Staff", style: const TextStyle(fontSize: 12)),
                trailing: ElevatedButton(
                  onPressed: _isProcessing ? null : () => _setPengganti(context, item),
                  style: ElevatedButton.styleFrom(backgroundColor: _elegantBlack, foregroundColor: Colors.white),
                  child: const Text("Pilih", style: TextStyle(fontSize: 12)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}