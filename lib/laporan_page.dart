import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class LaporanPage extends StatefulWidget {
  final String companyId;

  const LaporanPage({super.key, required this.companyId});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  // --- PALET WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _borderGrey = const Color(0xFFEEEEEE);
  final Color _elegantBlack = const Color(0xFF212121);

  final Color _statGreen = const Color(0xFF43A047);
  final Color _statRed = const Color(0xFFE53935);
  final Color _statOrange = const Color(0xFFFB8C00);
  final Color _statBlue = const Color(0xFF1E88E5);

  // Logic Variables
  int _totalKaryawan = 0;
  int _hadir = 0;
  int _izin = 0;
  int _terlambatCount = 0;
  int _totalTerlambatMenit = 0;
  bool _isLoading = true;

  DateTime _selectedDate = DateTime.now();

  // Data Lists
  List<Map<String, dynamic>> _detailHadir = [];        // Untuk Tampilan Harian
  List<Map<String, dynamic>> _detailHadirBulanan = []; // Untuk Rekap Gaji Bulanan

  // --- VARIABEL ATURAN GAJI ---
  int _toleransi = 15;
  double _dendaRingan = 1.0;
  double _dendaSedang = 2.5;
  double _dendaBerat = 5.0;

  @override
  void initState() {
    super.initState();
    _loadDataLengkap();
  }

  Future<void> _loadDataLengkap() async {
    setState(() => _isLoading = true);
    await _loadAturanGaji();
    await _hitungStatistik();
  }

  Future<void> _loadAturanGaji() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/settings/aturan_gaji")
          .get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        if (mounted) {
          setState(() {
            _toleransi = data['toleransi'] ?? 15;
            _dendaRingan = (data['denda_ringan'] ?? 1.0).toDouble();
            _dendaSedang = (data['denda_sedang'] ?? 2.5).toDouble();
            _dendaBerat = (data['denda_berat'] ?? 5.0).toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal load aturan gaji: $e");
    }
  }

  // Menghitung angka murni denda
  double _hitungPotonganValue(int menitTelat) {
    if (menitTelat <= _toleransi) return 0.0;
    if (menitTelat <= (_toleransi + 15)) return _dendaRingan;
    if (menitTelat <= (_toleransi + 45)) return _dendaSedang;
    return _dendaBerat;
  }

  // Mengubah denda menjadi teks untuk ditampilkan di UI
  String _hitungPotonganString(int menitTelat) {
    double nilai = _hitungPotonganValue(menitTelat);
    return "${nilai.toStringAsFixed(1)}%";
  }

  Future<void> _pilihTanggal(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: _elegantBlack, onPrimary: Colors.white, onSurface: _textBlack),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _isLoading = true;
      });
      _hitungStatistik();
    }
  }

  Future<void> _hitungStatistik() async {
    final db = FirebaseDatabase.instance.ref();
    String patternHari = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String patternBulan = DateFormat('yyyy-MM').format(_selectedDate);

    try {
      // 1. Ambil Total Karyawan Aktif
      final snapshotUser = await db.child("users")
          .orderByChild("company_id")
          .equalTo(widget.companyId)
          .get();
      int tempKaryawan = 0;
      if (snapshotUser.exists) {
        final userData = snapshotUser.value as Map;
        userData.forEach((k, v) {
          if (v is Map && v['role'] == 'karyawan' && (v['is_active'] ?? true)) {
            tempKaryawan++;
          }
        });
      }

      // 2. DATA HARIAN: Untuk Statistik Utama & List
      final snapshotAbsenHari = await db.child("companies/${widget.companyId}/absensi")
          .orderByChild("tanggal")
          .equalTo(patternHari)
          .get();

      int tempHadir = 0;
      int tempTerlambat = 0;
      int tempMenitTelat = 0;
      List<Map<String, dynamic>> tempDetailHari = [];

      if (snapshotAbsenHari.exists) {
        final data = snapshotAbsenHari.value as Map;
        data.forEach((k, v) {
          if (v is Map) {
            tempHadir++;
            bool lateFlag = v['is_telat'] == true;
            int menit = (v['menit_telat'] as num? ?? 0).toInt();
            if (lateFlag) {
              tempTerlambat++;
              tempMenitTelat += menit;
            }
            tempDetailHari.add({
              "tanggal": v['tanggal'],
              "nama": v['nama'],
              "email": v['email'],
              "jam": v['jam_masuk'] ?? v['jam'] ?? "-",
              "status": v['status'] ?? "Hadir",
              "is_telat": lateFlag,
              "menit_telat": menit,
            });
          }
        });
      }

      // 3. DATA BULANAN: Khusus Untuk Rekap Gaji Bulanan
      final snapshotAbsenBulan = await db.child("companies/${widget.companyId}/absensi")
          .orderByChild("tanggal")
          .startAt(patternBulan)
          .endAt("$patternBulan-31")
          .get();

      List<Map<String, dynamic>> tempDetailBulanan = [];
      if (snapshotAbsenBulan.exists) {
        final data = snapshotAbsenBulan.value as Map;
        data.forEach((k, v) {
          if (v is Map) {
            tempDetailBulanan.add({
              "email": v['email'] ?? "",
              "nama": v['nama'] ?? "User",
              "tanggal": v['tanggal'] ?? "-",
              "menit_telat": (v['menit_telat'] as num? ?? 0).toInt(),
            });
          }
        });
      }

      // 4. DATA IZIN HARIAN
      final snapshotIzin = await db.child("companies/${widget.companyId}/izin_karyawan")
          .orderByChild("tanggal")
          .equalTo(patternHari)
          .get();

      int tempIzin = 0;
      if (snapshotIzin.exists) {
        final data = snapshotIzin.value as Map;
        data.forEach((k, v) {
          if (v is Map) {
            String status = (v['status'] ?? '').toString().toLowerCase();
            if (status == 'disetujui' || status == 'approved') tempIzin++;
          }
        });
      }

      if (mounted) {
        setState(() {
          _totalKaryawan = tempKaryawan;
          _hadir = tempHadir;
          _terlambatCount = tempTerlambat;
          _totalTerlambatMenit = tempMenitTelat;
          _izin = tempIzin;
          _detailHadir = tempDetailHari;
          _detailHadirBulanan = tempDetailBulanan;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRekapGajiDialog() {
    Map<String, Map<String, dynamic>> rekapKaryawan = {};

    // Menggunakan data bulanan agar tidak terpengaruh filter tanggal di layar
    for (var data in _detailHadirBulanan) {
      String email = data['email'];
      String nama = data['nama'];
      int menitTelat = data['menit_telat'];

      if (!rekapKaryawan.containsKey(email)) {
        rekapKaryawan[email] = {
          'nama': nama,
          'total_telat_kali': 0,
          'total_potongan_persen': 0.0,
          'detail_pelanggaran': <String>[],
        };
      }

      double denda = _hitungPotonganValue(menitTelat);
      if (denda > 0) {
        rekapKaryawan[email]!['total_telat_kali'] += 1;
        rekapKaryawan[email]!['total_potongan_persen'] += denda;
        rekapKaryawan[email]!['detail_pelanggaran'].add(
            "${data['tanggal']}: Telat $menitTelat mnt (-$denda%)"
        );
      }
    }

    var listSanksi = rekapKaryawan.values.where((e) => e['total_potongan_persen'] > 0).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.monetization_on_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text("Rekap Potongan (Bulanan)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: listSanksi.isEmpty
              ? const Padding(
            padding: EdgeInsets.all(20),
            child: Text("Bulan ini bersih dari denda keterlambatan.", textAlign: TextAlign.center),
          )
              : ListView.separated(
            shrinkWrap: true,
            itemCount: listSanksi.length,
            separatorBuilder: (c, i) => const Divider(),
            itemBuilder: (c, i) {
              var k = listSanksi[i];
              return ExpansionTile(
                title: Text(k['nama'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Total Potongan: ${k['total_potongan_persen'].toStringAsFixed(1)}%", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                children: [
                  for (var d in k['detail_pelanggaran'])
                    ListTile(dense: true, title: Text(d, style: const TextStyle(fontSize: 12))),
                ],
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("TUTUP"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Laporan & Analisis", style: TextStyle(fontWeight: FontWeight.w600, color: _textBlack)),
        centerTitle: true,
        backgroundColor: _whiteCard,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _hitungStatistik,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderFilter(),
              const SizedBox(height: 16),
              _buildRekapButton(),
              const SizedBox(height: 24),
              _buildStatCards(),
              const SizedBox(height: 24),
              _buildChartSection(),
              const SizedBox(height: 30),
              const Text("Rincian Aktivitas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildAktivitasList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderFilter() {
    return InkWell(
      onTap: () => _pilihTanggal(context),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _whiteCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _borderGrey),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Periode Laporan", style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                Text(DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textBlack)),
              ],
            ),
            Icon(Icons.calendar_month_rounded, color: _elegantBlack),
          ],
        ),
      ),
    );
  }

  Widget _buildRekapButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showRekapGajiDialog,
        icon: const Icon(Icons.receipt_long_rounded, size: 18),
        label: Text("REKAP GAJI BULAN ${DateFormat('MMMM').format(_selectedDate).toUpperCase()}"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade50,
          foregroundColor: Colors.red,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.red.shade200)),
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    return Row(
      children: [
        _buildStatCard("Karyawan", "$_totalKaryawan", _statBlue, Icons.people_outline),
        _buildStatCard("Hadir", "$_hadir", _statGreen, Icons.fingerprint),
        _buildStatCard("Terlambat", "$_terlambatCount", _statRed, Icons.timer_outlined),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildChartSection() {
    double hadirTepat = (_hadir - _terlambatCount).toDouble();
    bool isEmpty = (_hadir + _izin) == 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _whiteCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: _borderGrey)),
      child: Column(
        children: [
          const Text("Komposisi Kehadiran", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                  sections: isEmpty
                      ? [PieChartSectionData(value: 1, color: _borderGrey, radius: 40, showTitle: false)]
                      : [
                    PieChartSectionData(value: hadirTepat > 0 ? hadirTepat : 0.1, color: _statGreen, title: 'Tepat', radius: 40, titleStyle: const TextStyle(color: Colors.white, fontSize: 10)),
                    PieChartSectionData(value: _terlambatCount.toDouble(), color: _statRed, title: 'Telat', radius: 40, titleStyle: const TextStyle(color: Colors.white, fontSize: 10)),
                    PieChartSectionData(value: _izin.toDouble(), color: _statOrange, title: 'Izin', radius: 40, titleStyle: const TextStyle(color: Colors.white, fontSize: 10)),
                  ]
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text("Akumulasi Telat Terpilih: $_totalTerlambatMenit Menit", style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAktivitasList() {
    if (_detailHadir.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Tidak ada riwayat untuk tanggal ini", style: TextStyle(color: Colors.grey))));
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _detailHadir.length,
      itemBuilder: (context, index) {
        final data = _detailHadir[index];
        bool isLate = data['is_telat'] == true;
        Color cardColor = isLate ? _statRed : (data['status'].toString().toLowerCase().contains('izin') ? _statOrange : _statGreen);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: cardColor.withValues(alpha: 0.3), blurRadius: 5)]),
          child: Row(
            children: [
              const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['nama'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    // Memanggil fungsi _hitungPotonganString untuk menghilangkan warning 'unused'
                    Text(
                        isLate
                            ? "${data['jam']} (Telat ${data['menit_telat']} mnt, Sanksi: ${_hitungPotonganString(data['menit_telat'])})"
                            : "${data['jam']}",
                        style: const TextStyle(color: Colors.white70, fontSize: 11)
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                child: Text(data['status'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
        );
      },
    );
  }
}