// File: lib/izin_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class IzinPage extends StatefulWidget {
  final String nama;
  final String email;
  final String companyId;

  const IzinPage({super.key, required this.nama, required this.email, required this.companyId});

  @override
  State<IzinPage> createState() => _IzinPageState();
}

class _IzinPageState extends State<IzinPage> {
  final TextEditingController _alasanController = TextEditingController();
  String _jenisIzin = 'Sakit';
  String _selectedShift = 'Pagi'; // ✅ Variabel baru untuk Shift
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // --- PALET WARNA (WHITE ELEGANT THEME) ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _whiteSurface = const Color(0xFFF5F5F5);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  // ==========================================
  // LOGIKA PENGIRIMAN & NOTIFIKASI
  // ==========================================

  void _kirimIzin() async {
    if (_alasanController.text.isEmpty) {
      _showErrorSnackBar("Mohon isi alasan izin.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref();
      String pathPerusahaan = "companies/${widget.companyId}";

      String tglFormat = DateFormat('yyyy-MM-dd').format(_selectedDate);
      String emailEnc = widget.email.replaceAll('.', '_').replaceAll('@', '_');
      String uniqueKey = "${emailEnc}_$tglFormat";

      // Data yang akan disimpan
      Map<String, dynamic> izinData = {
        "nama_karyawan": widget.nama,
        "email_karyawan": widget.email,
        "tanggal": tglFormat,
        "jenis_izin": _jenisIzin,
        "shift": _selectedShift, // ✅ Simpan Shift ke Database
        "status": "pending",
        "processed": false,
        "alasan": _alasanController.text,
        "timestamp": ServerValue.timestamp,
      };

      // 1. Simpan pengajuan ke folder perusahaan
      await ref.child("$pathPerusahaan/izin_karyawan/$uniqueKey").set(izinData);

      // 2. TRIGGER NOTIFIKASI KE MANAGER
      await ref.child("companies/${widget.companyId}/notif_manager/new_request").set({
        "pesan": "Pengajuan $_jenisIzin ($_selectedShift) dari ${widget.nama}",
        "waktu": ServerValue.timestamp,
        "type": "izin"
      });

      // 3. Catat Log Sistem
      await ref.child("companies/${widget.companyId}/logs").push().set({
        "admin": widget.nama,
        "aksi": "Mengajukan Izin ($_jenisIzin - $_selectedShift)",
        "timestamp": ServerValue.timestamp,
      });

      if (!mounted) return;
      _showSuccessDialog();

    } catch (e) {
      _showErrorSnackBar("Gagal kirim: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // UI COMPONENTS
  // ==========================================

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red[800],
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: _elegantBlack, onPrimary: Colors.white, onSurface: _textBlack),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _whiteCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 60),
            const SizedBox(height: 16),
            Text("Berhasil Terkirim", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _textBlack)),
            const SizedBox(height: 8),
            Text("Manager akan segera meninjau permohonan Anda.", textAlign: TextAlign.center, style: TextStyle(color: _textGrey)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
              style: ElevatedButton.styleFrom(backgroundColor: _elegantBlack, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text("KEMBALI KE BERANDA", style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: const Text("Form Pengajuan Izin", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _whiteCard,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 25),
            _buildFormContainer(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _elegantBlack, borderRadius: BorderRadius.circular(16)),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.white, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Status izin akan diperbarui otomatis setelah disetujui Manager.",
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormContainer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _whiteCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel("Jenis Pengajuan"),
          _buildDropdownIzin(), // Ubah nama fungsi biar jelas

          const SizedBox(height: 20),
          _buildLabel("Pilih Shift Kerja"), // ✅ Label Baru
          _buildDropdownShift(), // ✅ Dropdown Baru

          const SizedBox(height: 20),
          _buildLabel("Pilih Tanggal"),
          _buildDatePickerField(),

          const SizedBox(height: 20),
          _buildLabel("Alasan / Keterangan"),
          _buildTextField(),

          const SizedBox(height: 30),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  // --- SUB WIDGETS ---

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: _textBlack, fontSize: 14)),
  );

  Widget _buildDropdownIzin() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: _whiteSurface, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _jenisIzin,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: ['Sakit', 'Cuti', 'Izin Darurat', 'Lainnya']
              .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _jenisIzin = v!),
        ),
      ),
    );
  }

  // ✅ Widget Baru untuk Memilih Shift
  Widget _buildDropdownShift() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: _whiteSurface, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedShift,
          isExpanded: true,
          icon: const Icon(Icons.access_time_rounded), // Ikon Jam
          items: ['Pagi', 'Siang', 'Malam']
              .map((e) => DropdownMenuItem(value: e, child: Text("Shift $e"))).toList(),
          onChanged: (v) => setState(() => _selectedShift = v!),
        ),
      ),
    );
  }

  Widget _buildDatePickerField() {
    return InkWell(
      onTap: () => _selectDate(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _whiteSurface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate)), // Format Indonesia
            const Icon(Icons.calendar_month, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _alasanController,
      maxLines: 3,
      decoration: InputDecoration(
        filled: true,
        fillColor: _whiteSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintText: "Contoh: Mengantar orang tua ke RS...",
        hintStyle: TextStyle(color: _textGrey.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _kirimIzin,
        style: ElevatedButton.styleFrom(
            backgroundColor: _elegantBlack,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0
        ),
        child: _isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text("KIRIM PENGAJUAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }
}