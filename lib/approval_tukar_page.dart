import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class ApprovalTukarPage extends StatefulWidget {
  final String companyId;
  final String myEmail;
  final String myRole;

  const ApprovalTukarPage({super.key, required this.companyId, required this.myEmail, required this.myRole});

  @override
  State<ApprovalTukarPage> createState() => _ApprovalTukarPageState();
}

class _ApprovalTukarPageState extends State<ApprovalTukarPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // --- PERBAIKAN LOGIC (ATOMIC UPDATE) ---
  // --- LOGIKA BARU: TUKAR POSISI (SWAP) ---
  Future<void> _approveByManager(String key, Map data) async {
    try {
      String date = data['shift_date'];
      String requesterEmail = data['requester_email'];
      String targetEmail = data['target_email'];

      String requesterEmailEnc = requesterEmail.replaceAll('.', '_').replaceAll('@', '_');
      String targetEmailEnc = targetEmail.replaceAll('.', '_').replaceAll('@', '_');

      // Key Database untuk Shift masing-masing
      String keyJadwalA = "${requesterEmailEnc}_$date"; // Jadwal A (Pemohon)
      String keyJadwalB = "${targetEmailEnc}_$date";    // Jadwal B (Target)

      DatabaseReference shiftRef = _dbRef.child("companies/${widget.companyId}/shifts");

      // 1. AMBIL JADWAL SI B (TARGET) DULU DARI DATABASE
      final snapshotB = await shiftRef.child(keyJadwalB).get();

      Map<String, Object?> updates = {};

      // Data Shift A (Sudah ada di request)
      Map shiftDataA = {
        "company_id": widget.companyId,
        "email": targetEmail, // Pindahkan ke B
        "nama_karyawan": data['target_name'],
        "tanggal": date,
        "shift": data['shift_name'], // Shift A yang lama
        "jam_mulai": data['jam_mulai'],
        "jam_selesai": data['jam_selesai'],
        "jenis": "tukar_shift",
        "created_at": ServerValue.timestamp,
      };

      // Cek apakah Si B punya jadwal di hari itu?
      if (snapshotB.exists && snapshotB.value != null) {
        // --- SKENARIO 1: TUKAR GULING (A Punya Jadwal, B Punya Jadwal) ---
        // Kita ambil data shift B, lalu ubah pemiliknya jadi A

        Map originalShiftB = Map<String, dynamic>.from(snapshotB.value as Map);

        Map shiftDataBToA = {
          "company_id": widget.companyId,
          "email": requesterEmail, // Pindahkan ke A
          "nama_karyawan": data['requester_name'],
          "tanggal": date,
          "shift": originalShiftB['shift'],       // Shift B yang lama
          "jam_mulai": originalShiftB['jam_mulai'],
          "jam_selesai": originalShiftB['jam_selesai'],
          "jenis": "tukar_shift",
          "created_at": ServerValue.timestamp,
        };

        // Update DB: A dapat jadwal B, B dapat jadwal A
        updates["companies/${widget.companyId}/shifts/$keyJadwalA"] = shiftDataBToA;
        updates["companies/${widget.companyId}/shifts/$keyJadwalB"] = shiftDataA;

      } else {
        // --- SKENARIO 2: LEMPAR JADWAL (B Libur, A ngasih jadwal ke B) ---
        // A jadi kosong (libur), B jadi masuk menggantikan A

        updates["companies/${widget.companyId}/shifts/$keyJadwalA"] = null; // A Dihapus
        updates["companies/${widget.companyId}/shifts/$keyJadwalB"] = shiftDataA; // B Dibuat
      }

      // Update Status Request jadi Approved
      updates["companies/${widget.companyId}/shift_swaps/$key/status"] = "approved";
      updates["companies/${widget.companyId}/shift_swaps/$key/approved_at"] = ServerValue.timestamp;

      // Eksekusi Semua Perubahan
      await _dbRef.update(updates);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Berhasil! Jadwal telah ditukar."), backgroundColor: Colors.green));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _updateStatus(String key, String newStatus) async {
    await _dbRef.child("companies/${widget.companyId}/shift_swaps/$key").update({"status": newStatus});
  }

  // Helper untuk format tanggal agar aman dari error locale
  String _formatDate(String dateStr) {
    try {
      // Coba pakai Locale ID, jika error pakai default
      return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.parse(dateStr));
    } catch (e) {
      return dateStr; // Fallback jika gagal format
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isManager = widget.myRole == 'manager' || widget.myRole == 'owner';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Persetujuan Tukar Shift", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: StreamBuilder(
        stream: _dbRef.child("companies/${widget.companyId}/shift_swaps").onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text("Belum ada pengajuan tukar shift."));
          }

          // Safety Cast
          final rawVal = snapshot.data!.snapshot.value;
          Map rawData = (rawVal is Map) ? rawVal : {}; // Pastikan Map

          List<Map> listData = [];
          rawData.forEach((key, value) {
            if(value is Map) {
              listData.add({"key": key, ...value});
            }
          });

          // Filter Data Sesuai Role
          List<Map> filteredList = listData.where((item) {
            String status = item['status'] ?? '';
            String targetEmail = item['target_email'] ?? '';

            if (!isManager) {
              // Karyawan B: Lihat yang status 'pending_target' DAN untuk saya
              return targetEmail == widget.myEmail && status == 'pending_target';
            } else {
              // Manager: Lihat yang 'pending_manager'
              return status == 'pending_manager';
            }
          }).toList();

          if (filteredList.isEmpty) {
            return const Center(child: Text("Tidak ada pengajuan yang perlu diproses."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredList.length,
            itemBuilder: (context, index) {
              final item = filteredList[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.swap_horiz_rounded, color: Colors.blue, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${item['requester_name']} ➔ ${item['target_name']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(_formatDate(item['shift_date']), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Text("Shift: ${item['shift_name']} (${item['jam_mulai']} - ${item['jam_selesai']})"),
                      Text("Alasan: ${item['alasan'] ?? '-'}", style: const TextStyle(fontStyle: FontStyle.italic)),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => _updateStatus(item['key'], "rejected"),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text("TOLAK"),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              if (isManager) {
                                _approveByManager(item['key'], item);
                              } else {
                                _updateStatus(item['key'], "pending_manager");
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            child: Text(isManager ? "SETUJUI & TUKAR" : "TERIMA"),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}