import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class FormTukarShiftPage extends StatefulWidget {
  final String companyId;
  final String myEmail;
  final String myName;
  final Map<String, dynamic> shiftData;

  const FormTukarShiftPage({
    super.key,
    required this.companyId,
    required this.myEmail,
    required this.myName,
    required this.shiftData,
  });

  @override
  State<FormTukarShiftPage> createState() => _FormTukarShiftPageState();
}

class _FormTukarShiftPageState extends State<FormTukarShiftPage> {
  final _keteranganController = TextEditingController();
  String? _selectedTargetEmail;
  String? _selectedTargetName;
  bool _isLoading = false;

  // --- TEMA KONSISTEN RAKSASA (HITAM PUTIH CONTRAST) ---
  final Color _bgSurface = const Color(0xFFE0E0E0); // Abu kontras
  final Color _white = Colors.white;
  final double _borderWidth = 3.0; // Garis tebal

  // ==========================================
  // LOGIKA (TETAP SAMA SEPERTI ASLIMU)
  // ==========================================

  void _kirimPengajuan() async {
    // Validasi
    if (_selectedTargetEmail == null || _keteranganController.text.trim().isEmpty) {
      _showSnackBar("ISI REKAN & ALASAN!", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      String emailEnc = widget.myEmail.replaceAll('.', '_').replaceAll('@', '_');
      String tgl = widget.shiftData['tanggal'];
      // Key Database Shift Asli kamu
      String shiftKey = widget.shiftData['key'] ?? "${emailEnc}_$tgl";

      await FirebaseDatabase.instance.ref("companies/${widget.companyId}/shift_swaps").push().set({
        "requester_email": widget.myEmail,
        "requester_name": widget.myName,
        "target_email": _selectedTargetEmail,
        "target_name": _selectedTargetName,
        "shift_date": tgl,
        "shift_name": widget.shiftData['shift'] ?? "Shift",
        "jam_mulai": widget.shiftData['jam_mulai'],
        "jam_selesai": widget.shiftData['jam_selesai'],
        "original_shift_key": shiftKey,
        "alasan": _keteranganController.text.trim(),
        "status": "pending_target",
        "created_at": ServerValue.timestamp,
      });

      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar("PENGAJUAN TERKIRIM!", isError: false);
    } catch (e) {
      _showSnackBar("GAGAL: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.w900)),
      backgroundColor: isError ? Colors.red : Colors.green, //Ivan didn't ask to change error/success colors, just general "hitamputih" style
    ));
  }

  // ==========================================
  // UI WIDGETS (GAYA RAKSASA WIREFRAME)
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSurface,
      appBar: AppBar(
        title: const Text("AJUKAN TUKAR SHIFT",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.black)),
        centerTitle: true,
        backgroundColor: _white,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: Colors.black, width: _borderWidth)),
        iconTheme: const IconThemeData(color: Colors.black, size: 30),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGiantLabel("DETAIL SHIFT ANDA"),
            _buildMyShiftCardGiant(),

            const SizedBox(height: 30),
            _buildGiantLabel("PILIH REKAN PENGGANTI"),
            _buildColleagueDropdownGiant(),

            const SizedBox(height: 30),
            _buildGiantLabel("ALASAN PENUKARAN"),
            _buildGiantTextField(),

            const SizedBox(height: 40),

            // TOMBOL KIRIM RAKSASA (HITAM SOLID)
            _buildSubmitButtonGiant(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildGiantLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text.toUpperCase(),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1.5)),
  );

  Widget _buildMyShiftCardGiant() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _white,
          border: Border.all(color: Colors.black, width: _borderWidth)
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _bgSurface, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)),
            child: const Icon(Icons.calendar_today, color: Colors.black, size: 30),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("SHIFT ANDA:", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w900, fontSize: 12)),
                Text("${widget.shiftData['tanggal']}",
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text("${widget.shiftData['shift']} (${widget.shiftData['jam_mulai']} - ${widget.shiftData['jam_selesai']})",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColleagueDropdownGiant() {
    // ✅ KODE ASLI KAMU UNTUK FILTER KARYAWAN TETAP AKTIF
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref("users").orderByChild("company_id").equalTo(widget.companyId).onValue,
      builder: (context, snapshot) {
        List<Map<String, String>> rekanList = [];
        if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
          final raw = snapshot.data!.snapshot.value as Map;
          raw.forEach((key, value) {
            final u = Map<String, dynamic>.from(value as Map);
            String role = (u['role'] ?? "").toString().toLowerCase();
            // Filter: Bukan diri sendiri AND harus karyawan/staff
            if (u['email'] != widget.myEmail && (role == 'karyawan' || role == 'staff')) {
              rekanList.add({'email': u['email'], 'nama': u['nama']});
            }
          });
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          decoration: BoxDecoration(color: _white, border: Border.all(color: Colors.black, width: 2.5)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTargetEmail,
              isExpanded: true,
              hint: const Text("CARI REKAN...", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black26)),
              icon: const Icon(Icons.person_search, color: Colors.black, size: 30),
              items: rekanList.map((k) => DropdownMenuItem(
                  value: k['email'],
                  child: Text(k['nama']!.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))
              )).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedTargetEmail = val;
                  _selectedTargetName = rekanList.firstWhere((e) => e['email'] == val)['nama'];
                });
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildGiantTextField() {
    return TextField(
      controller: _keteranganController,
      maxLines: 3,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
      decoration: InputDecoration(
        filled: true, fillColor: _bgSurface,
        hintText: "CONTOH: MAU ADA ACARA KELUARGA MENDADAK...",
        hintStyle: const TextStyle(color: Colors.black26, fontWeight: FontWeight.w900),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black, width: 2.5)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black, width: 4.0)),
        contentPadding: const EdgeInsets.all(20),
      ),
    );
  }

  Widget _buildSubmitButtonGiant() {
    return SizedBox(
      width: double.infinity,
      height: 75, //Large height
      child: ElevatedButton(
        onPressed: _isLoading ? null : _kirimPengajuan,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black, //Hitam solid
          shape: const RoundedRectangleBorder(), //Square corners
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text("KIRIM PENGAJUAN",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
      ),
    );
  }
}