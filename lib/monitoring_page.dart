import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class MonitoringPage extends StatefulWidget {
  final String companyId; // ✅ 1. Tambahkan variabel penampung

  const MonitoringPage({super.key, required this.companyId}); // ✅ 2. Masukkan ke constructor

  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {
  final String tanggalHariIni = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // --- PALET WARNA (WHITE ELEGANT THEME) ---
  final Color _bgScaffold = const Color(0xFFF8F9FA); // Background Abu Muda
  final Color _whiteCard = const Color(0xFFFFFFFF);  // Putih Murni
  final Color _textBlack = const Color(0xFF1A1A1A);  // Hitam Utama
  final Color _textGrey = const Color(0xFF757575);   // Abu Teks
  final Color _borderGrey = const Color(0xFFEEEEEE); // Garis Tipis

  // Status Colors (Soft Pastel)
  final Color _activeGreen = const Color(0xFF4CAF50); // Hijau (Shift Aktif)
  final Color _inactiveGrey = const Color(0xFFBDBDBD); // Abu (Selesai)
  final Color _lateRed = const Color(0xFFE53935); // Merah (Terlambat)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text(
          "Monitoring Harian",
          style: TextStyle(fontWeight: FontWeight.w600, color: _textBlack),
        ),
        centerTitle: true,
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textBlack),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: _borderGrey, height: 1.0),
        ),
      ),
      body: StreamBuilder(
        stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/absensi").onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: _textBlack));
          }

          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            Map<dynamic, dynamic> dataAbsen = snapshot.data!.snapshot.value as Map;
            List<Map<dynamic, dynamic>> listHadir = [];

            dataAbsen.forEach((key, value) {
              if (value is! Map) return;
              if (value['tanggal'] == tanggalHariIni) {
                listHadir.add(value);
              }
            });

            // lib/monitoring_page.dart

// Statistik (Pastikan string sesuai dengan yang disimpan di absensi_page)
            // Cari bagian perhitungan statistik:
            int totalHadir = listHadir.length;
// Aktif jika sudah masuk tapi belum ada jam_keluar
            int sedangShift = listHadir.where((e) => e['jam_keluar'] == null || e['jam_keluar'] == "").length;
// Selesai jika jam_keluar sudah terisi
            int sudahPulang = listHadir.where((e) => e['jam_keluar'] != null && e['jam_keluar'] != "").length;

            if (listHadir.isEmpty) return _buildEmptyState();

            // Sorting (Terbaru di atas)
            listHadir.sort((a, b) {
              String jamA = a['jam_masuk'] ?? "00:00";
              String jamB = b['jam_masuk'] ?? "00:00";
              return jamB.compareTo(jamA);
            });

            return Column(
              children: [
                // === HEADER STATISTIK (Minimalist Card) ===
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _whiteCard,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5)),
                    ],
                    border: Border.all(color: _borderGrey),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem("Total", totalHadir.toString(), Colors.blue, Icons.people_outline),
                      _buildVerticalDivider(),
                      _buildStatItem("Aktif", sedangShift.toString(), _activeGreen, Icons.access_time),
                      _buildVerticalDivider(),
                      _buildStatItem("Selesai", sudahPulang.toString(), _textGrey, Icons.check_circle_outline),
                    ],
                  ),
                ),

                // === LIST KARYAWAN ===
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: listHadir.length,
                    itemBuilder: (context, index) {
                      final item = listHadir[index];
                      bool isCheckOut = item['status'] == "Check-out";
                      bool isLate = item['keterangan'] != null && item['keterangan'].toString().contains("Terlambat");

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _whiteCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _borderGrey),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: isCheckOut ? _inactiveGrey.withValues(alpha: 0.1) : _activeGreen.withValues(alpha: 0.1),
                                  child: Text(
                                    (item['nama'] ?? "?")[0].toUpperCase(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isCheckOut ? _textGrey : _activeGreen,
                                    ),
                                  ),
                                ),
                                if (isLate)
                                  Positioned(
                                    right: 0, bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                      // PERBAIKAN: Menggunakan _lateRed disini
                                      child: Icon(Icons.warning, size: 14, color: _lateRed),
                                    ),
                                  )
                              ],
                            ),
                            title: Text(
                              item['nama'] ?? "Tanpa Nama",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _textBlack),
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isCheckOut ? _textGrey.withValues(alpha: 0.1) : _activeGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isCheckOut ? "Selesai Shift" : "Sedang Bekerja",
                                    style: TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.bold,
                                      color: isCheckOut ? _textGrey : _activeGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              const Divider(height: 1, thickness: 1, color: Color(0xFFF5F5F5)),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(child: _buildTimeInfo("Masuk", item['jam_masuk'] ?? "-", Icons.login, _activeGreen)),
                                  Expanded(child: _buildTimeInfo("Keluar", item['jam_keluar'] ?? "--:--", Icons.logout, isCheckOut ? Colors.orange : _textGrey)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _bgScaffold,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.location_on_outlined, size: 14, color: _textGrey),
                                        const SizedBox(width: 6),
                                        Text("Lokasi", style: TextStyle(fontSize: 11, color: _textGrey, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Jarak: ${item['jarak'] ?? 0} meter dari titik pusat",
                                      style: TextStyle(fontSize: 12, color: _textBlack),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }
          return _buildEmptyState();
        },
      ),
    );
  }

  // --- WIDGET HELPERS ---

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textBlack)),
        Text(label, style: TextStyle(fontSize: 11, color: _textGrey)),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(height: 30, width: 1, color: _borderGrey);
  }

  Widget _buildTimeInfo(String label, String time, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: _textGrey)),
            Text(time, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _textBlack)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_outlined, size: 50, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text("Belum ada data hari ini", style: TextStyle(color: _textGrey, fontSize: 14)),
        ],
      ),
    );
  }
}