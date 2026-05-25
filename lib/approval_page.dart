import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'pilih_pengganti_page.dart';

class ApprovalPage extends StatefulWidget {
  final String companyId;

  const ApprovalPage({super.key, required this.companyId});

  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> {
  // --- PALET WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  final Color _successGreen = const Color(0xFF2E7D32);
  final Color _warningOrange = const Color(0xFFEF6C00);
  final Color _errorRed = const Color(0xFFC62828);

  // --- LOGIKA UPDATE STATUS (TOLAK) ---
  void _updateStatus(String key, String statusBaru, String namaKaryawan) async {
    try {
      // ✅ FIX: Simpan log ke folder perusahaan (Bukan Global)
      await FirebaseDatabase.instance.ref("companies/${widget.companyId}/logs").push().set({
        "admin": "Manajer Operasional",
        "aksi": "$statusBaru izin untuk $namaKaryawan",
        "timestamp": ServerValue.timestamp,
      });

      await FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/izin_karyawan")
          .child(key)
          .update({
        "status": "rejected",
        "processed": true,
        "tgl_keputusan": DateTime.now().toString(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Berhasil di-$statusBaru"), backgroundColor: _elegantBlack),
      );
    } catch (e) {
      debugPrint("Error Update: $e");
    }
  }

  // --- LOGIKA APPROVE (SETUJU) ---
  // Di lib/approval_page.dart pada fungsi _approveLeave
  Future<bool> _approveLeave(Map item, String key) async { // Tambahkan parameter 'item'
    try {
      // Kita update status, TAPI kita juga pastikan data inti tersimpan ulang
      // jaga-jaga kalau data lama ternyata korup/hilang sebagian.
      await FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/izin_karyawan")
          .child(key)
          .update({
        "status": "approved",
        "processed": true,
        "tgl_keputusan": DateTime.now().toString(),

        // RE-SAVE DATA PENTING (Agar tidak hilang)
        "nama_karyawan": item['nama_karyawan'],
        "email_karyawan": item['email_karyawan'],
        "tanggal": item['tanggal'],
        "alasan": item['alasan'],
        "jenis_izin": item['jenis_izin'],
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // --- LOGIKA HAPUS SHIFT ---
  void _hapusShiftTanpaPengganti(String? email, String? tanggal) async {
    if (email == null || email.isEmpty || tanggal == null || tanggal.isEmpty) return;

    String emailEnc = email.replaceAll('.', '_').replaceAll('@', '_');
    String keyJadwal = "${emailEnc}_$tanggal";

    await FirebaseDatabase.instance
        .ref("companies/${widget.companyId}/shifts/$keyJadwal")
        .remove();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Persetujuan Izin", style: TextStyle(color: _textBlack, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: _whiteCard,
        elevation: 0,
        iconTheme: IconThemeData(color: _textBlack),
      ),
      body: StreamBuilder(
        stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/izin_karyawan").onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ✅ Tampilan saat data benar-benar tidak ada di Firebase
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_rounded, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "Belum ada pengajuan izin",
                    style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }

          final rawData = snapshot.data!.snapshot.value;
          Map<dynamic, dynamic> data = (rawData is Map) ? rawData : (rawData as List).asMap();

          List listIzin = [];
          data.forEach((k, v) {
            if (v != null) {
              // Filter: Hanya ambil yang statusnya 'pending'
              String status = (v['status'] ?? "").toString().toLowerCase();
              if (status == 'pending' || v['processed'] != true) {
                v['key'] = k.toString();
                listIzin.add(v);
              }
            }
          });

          // ✅ Tampilan saat data ada di Firebase tapi semuanya sudah diproses (list kosong)
          if (listIzin.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.done_all_rounded, size: 60, color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    "Semua izin sudah diproses",
                    style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }

          listIzin.sort((a, b) => (b['tanggal'] ?? "").compareTo(a['tanggal'] ?? ""));

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: listIzin.length,
            itemBuilder: (context, index) => _buildIzinCard(listIzin[index]),
          );
        },
      ),
    );
  }

  Widget _buildIzinCard(Map item) {
    String rawStatus = (item['status'] ?? "pending").toString().toLowerCase();
    String displayStatus = rawStatus == "pending" ? "Menunggu" : rawStatus;

    bool isPending = rawStatus == 'pending' || rawStatus == 'menunggu persetujuan';

    Color statusColor;
    if (rawStatus == 'approved' || rawStatus == 'disetujui') {
      statusColor = _successGreen;
    } else if (rawStatus == 'rejected' || rawStatus == 'ditolak') {
      statusColor = _errorRed;
    } else {
      statusColor = _warningOrange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _whiteCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: _borderGrey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item['nama_karyawan'] ?? "User",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                // ✅ FIX DEPRECATED: withOpacity -> withValues
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(
                    displayStatus.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)
                ),
              ),
            ],
          ),
          const Divider(height: 30),
          Row(
            children: [
              Expanded(child: _buildInfoItem(Icons.calendar_today, "Tanggal", item['tanggal'] ?? "-")),
              Expanded(child: _buildInfoItem(Icons.category, "Tipe", item['jenis_izin'] ?? "-")),
            ],
          ),
          const SizedBox(height: 15),
          Text("Keterangan:", style: TextStyle(fontSize: 11, color: _textGrey, fontWeight: FontWeight.bold)),
          Text(item['alasan'] ?? "-", style: const TextStyle(fontSize: 13)),

          if (isPending) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _updateStatus(item['key'], 'Ditolak', item['nama_karyawan']),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _errorRed,
                        // ✅ FIX DEPRECATED: withOpacity -> withValues
                        side: BorderSide(color: _errorRed.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)
                    ),
                    child: const Text("TOLAK"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showApprovalDialog(item),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _elegantBlack,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)
                    ),
                    child: const Text("SETUJUI"),
                  ),
                ),
              ],
            )
          ]
        ],
      ),
    );
  }

  void _showApprovalDialog(Map item) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Izin Disetujui", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Apakah Anda ingin menugaskan karyawan pengganti untuk mengisi shift ini?"),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);

              // ✅ PERBAIKAN DI SINI: Kirim 'item' sebagai parameter pertama
              await _approveLeave(item, item['key']);

              _hapusShiftTanpaPengganti(item['email_karyawan'] ?? "", item['tanggal'] ?? "");
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Izin disetujui (Jadwal dikosongkan)")));
            },
            child: Text("TIDAK PERLU", style: TextStyle(color: _textGrey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);

              // ✅ PERBAIKAN DI SINI JUGA: Kirim 'item' sebagai parameter pertama
              await _approveLeave(item, item['key']);

              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PilihPenggantiPage(
                  namaYangIzin: item['nama_karyawan'] ?? "",
                  emailYangIzin: item['email_karyawan'] ?? "",
                  tanggalIzin: item['tanggal'] ?? "",
                  izinKey: item['key'],
                  companyId: widget.companyId,
                ),
              ));
            },
            style: ElevatedButton.styleFrom(backgroundColor: _elegantBlack),
            child: const Text("PILIH PENGGANTI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, size: 12, color: _textGrey), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 11, color: _textGrey))]),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}