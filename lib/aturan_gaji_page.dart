import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AturanGajiPage extends StatefulWidget {
  final String companyId;
  const AturanGajiPage({super.key, required this.companyId});

  @override
  State<AturanGajiPage> createState() => _AturanGajiPageState();
}

class _AturanGajiPageState extends State<AturanGajiPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // --- STATE DEFAULT ---
  int _toleransi = 15; // Menit
  double _dendaRingan = 1.0; // %
  double _dendaSedang = 2.5; // %
  double _dendaBerat = 5.0; // %
  bool _isLoading = true;

  // --- WARNA ---
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _bgScaffold = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final snapshot = await _dbRef
          .child("companies/${widget.companyId}/settings/aturan_gaji")
          .get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          _toleransi = data['toleransi'] ?? 15;
          _dendaRingan = (data['denda_ringan'] ?? 1.0).toDouble();
          _dendaSedang = (data['denda_sedang'] ?? 2.5).toDouble();
          _dendaBerat = (data['denda_berat'] ?? 5.0).toDouble();
        });
      }
    } catch (e) {
      debugPrint("Gagal load aturan gaji: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _simpanAturan() async {
    setState(() => _isLoading = true);
    try {
      await _dbRef.child("companies/${widget.companyId}/settings/aturan_gaji").set({
        "toleransi": _toleransi,
        "denda_ringan": _dendaRingan,
        "denda_sedang": _dendaSedang,
        "denda_berat": _dendaBerat,
        "updated_at": ServerValue.timestamp,
      });

      // ✅ PERBAIKAN: Cek mounted sebelum pakai context (Menghilangkan warning async gaps)
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aturan Gaji Berhasil Disimpan!"), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal simpan: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- LOGIKA HITUNG RANGE OTOMATIS ---
    int ringanStart = _toleransi + 1;
    int ringanEnd = _toleransi + 15;

    int sedangStart = ringanEnd + 1;
    int sedangEnd = ringanEnd + 30;

    int beratStart = sedangEnd; // Lebih dari ini

    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: const Text("Aturan Potongan Gaji", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader("Toleransi Keterlambatan", "Batas waktu keterlambatan yang masih dianggap aman (0%)."),
            const SizedBox(height: 10),

            // SLIDER TOLERANSI
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  // ✅ PERBAIKAN: Hapus kurung kurawal berlebih pada string interpolation
                  Text("$_toleransi Menit", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _elegantBlack)),
                  Slider(
                    value: _toleransi.toDouble(),
                    min: 0,
                    max: 60,
                    divisions: 60,
                    activeColor: _elegantBlack,
                    label: "$_toleransi menit",
                    onChanged: (val) => setState(() => _toleransi = val.toInt()),
                  ),
                  const Text("Geser untuk mengubah toleransi"),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildHeader("Persentase Denda", "Besaran potongan gaji berdasarkan kategori."),
            const SizedBox(height: 10),

            // INPUT PERSEN
            _buildInputPersen("Potongan Ringan (%)", _dendaRingan, (val) => setState(() => _dendaRingan = val)),
            const SizedBox(height: 10),
            _buildInputPersen("Potongan Sedang (%)", _dendaSedang, (val) => setState(() => _dendaSedang = val)),
            const SizedBox(height: 10),
            _buildInputPersen("Potongan Berat (%)", _dendaBerat, (val) => setState(() => _dendaBerat = val)),

            const SizedBox(height: 30),

            // --- TABEL ATURAN DINAMIS ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200)
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Text("Simulasi Aturan Saat Ini", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ]),
                  const Divider(color: Colors.orange),
                  const SizedBox(height: 8),
                  _buildRowSimulasi("✅ Aman (0%)", "Telat 0 - $_toleransi menit"),
                  _buildRowSimulasi("⚠️ Ringan ($_dendaRingan%)", "Telat $ringanStart - $ringanEnd menit"),
                  _buildRowSimulasi("⚠️ Sedang ($_dendaSedang%)", "Telat $sedangStart - $sedangEnd menit"),
                  _buildRowSimulasi("⛔ Berat ($_dendaBerat%)", "Telat > $beratStart menit"),
                ],
              ),
            ),

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _simpanAturan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _elegantBlack,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("SIMPAN ATURAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildInputPersen(String label, double value, Function(double) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: value.toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(border: InputBorder.none, hintText: "0.0"),
              onChanged: (val) {
                if (val.isNotEmpty) onChanged(double.tryParse(val) ?? 0.0);
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRowSimulasi(String label, String range) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(range, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }
}