import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:lottie/lottie.dart';
import 'notification_helper.dart';

class AbsensiPage extends StatefulWidget {
  final String nama;
  final String email;
  final String companyId;

  const AbsensiPage({
    super.key,
    required this.nama,
    required this.email,
    required this.companyId
  });

  @override
  State<AbsensiPage> createState() => _AbsensiPageState();
}

class _AbsensiPageState extends State<AbsensiPage> {
  // --- KONTROL SCANNER (DIPINDAHKAN KE SINI AGAR BISA DIAKSES SEMUA FUNGSI) ---
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  // --- KONFIGURASI LOKASI ---
  double _latKafe = 0.0;
  double _lngKafe = 0.0;
  int _radiusMaksimal = 150;
  final Distance _distance = const Distance();

  bool _isLoading = false;
  bool _isSettingLoaded = false;
  String _statusLokasi = "Mengambil data lokasi...";
  Position? _currentPosition;
  double _jarak = 0.0;
  bool _diDalamArea = false;

  // --- TEMA WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _statusGreen = const Color(0xFF2E7D32);
  final Color _statusRed = const Color(0xFFC62828);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  @override
  void initState() {
    super.initState();
    _ambilSettingLokasi();
  }

  @override
  void dispose() {
    // ✅ PENTING: Matikan mesin scanner saat keluar halaman agar RAM tidak penuh
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _ambilSettingLokasi() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/location")
          .get();

      if (snapshot.exists) {
        final data = snapshot.value;
        if (data is Map && mounted) {
          setState(() {
            _latKafe = (data['lat'] as num).toDouble();
            _lngKafe = (data['lng'] as num).toDouble();
            _radiusMaksimal = (data['radius'] as num?)?.toInt() ?? 150;
            _isSettingLoaded = true;
          });
          _cekLokasiDanIzin();
        }
      } else {
        if (mounted) setState(() => _statusLokasi = "Lokasi Kafe Belum Diatur");
      }
    } catch (e) {
      if (mounted) setState(() => _statusLokasi = "Gagal Ambil Konfigurasi");
    }
  }

  Future<void> _cekLokasiDanIzin() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _statusLokasi = "GPS Tidak Aktif");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _statusLokasi = "Izin Lokasi Ditolak");
        return;
      }
    }

    try {
      // ✅ GANTI KODE LAMA DENGAN INI
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      double jarakMeter = _distance.as(
          LengthUnit.Meter,
          LatLng(_latKafe, _lngKafe),
          LatLng(position.latitude, position.longitude)
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _jarak = jarakMeter;
          _diDalamArea = jarakMeter <= _radiusMaksimal;
          _statusLokasi = _diDalamArea ? "Lokasi Valid (Di Area)" : "Lokasi Terlalu Jauh";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusLokasi = "Gagal Ambil Koordinat");
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isLoading || !_isSettingLoaded || !_diDalamArea) return;

    try {
      final tokenSnap = await FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/settings/qr_code/token")
          .get();

      if (!tokenSnap.exists) {
        _showErrorDialog("Error", "Token absensi belum diatur oleh Admin.");
        return;
      }

      String activeToken = tokenSnap.value.toString().trim();
      bool isQrValid = false;

      for (final barcode in capture.barcodes) {
        if (barcode.rawValue?.trim() == activeToken) {
          isQrValid = true;
          // ✅ QR VALID: Hentikan scanner segera agar tidak double scan
          await _scannerController.stop();
          break;
        }
      }

      if (!isQrValid) {
        _showErrorDialog("Gagal", "Kode QR tidak valid atau sudah kedaluwarsa.");
        return;
      }

      setState(() => _isLoading = true);
      _prosesValidasiJadwal();
    } catch (e) {
      _showErrorDialog("Error", "Gagal memproses data: $e");
    }
  }

  void _prosesValidasiJadwal() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String emailEnc = widget.email.replaceAll('.', '_').replaceAll('@', '_');

    final shiftSnap = await FirebaseDatabase.instance
        .ref("companies/${widget.companyId}/shifts/${emailEnc}_$today")
        .get();

    if (shiftSnap.exists) {
      final data = shiftSnap.value as Map;
      String jamMulai = data['jam_mulai'].toString();
      String shiftName = data['shift']?.toString() ?? data['nama_shift']?.toString() ?? "-";
      String jamSelesai = data['jam_selesai']?.toString() ?? "--:--";

      // --- 🛡️ LOGIKA BARU: CEK JENDELA WAKTU ---
      try {
        DateTime sekarang = DateTime.now();
        DateFormat formatJam = DateFormat("HH:mm");

        // Ambil jam mulai dari database (misal "13:00")
        DateTime jamJadwal = formatJam.parse(jamMulai);

        // Buat jadi waktu lengkap hari ini (21 Jan 2026, 13:00)
        DateTime waktuMulaiShift = DateTime(
            sekarang.year, sekarang.month, sekarang.day,
            jamJadwal.hour, jamJadwal.minute
        );

        // Batasan: Maksimal 2 Jam sebelum shift (Bisa kamu ganti sesukamu)
        DateTime batasAwalAbsen = waktuMulaiShift.subtract(const Duration(hours: 1));

        if (sekarang.isBefore(batasAwalAbsen)) {
          // ❌ Terlalu pagi
          _showErrorDialog(
              "Terlalu Awal",
              "Shift Anda jam $jamMulai. Anda baru bisa absen mulai jam ${formatJam.format(batasAwalAbsen)}."
          );
          _scannerController.start(); // Hidupkan kamera lagi
          setState(() => _isLoading = false);
          return; // Berhenti di sini, jangan lanjut simpan
        }
      } catch (e) {
        debugPrint("Gagal hitung jendela waktu: $e");
      }

      // ✅ Jika lolos pengecekan waktu, baru jalankan ini
      _prosesSimpanAbsensi(jamMulai, shiftName, jamSelesai);
    } else {
      _showErrorDialog("Akses Ditolak", "Jadwal Anda hari ini tidak ditemukan.");
      _scannerController.start();
      setState(() => _isLoading = false);
    }
  }

  void _prosesSimpanAbsensi(String jamMulaiJadwal, String shiftName, String jamSelesaiJadwal) async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String jamSekarang = DateFormat('HH:mm').format(DateTime.now());
    String emailEnc = widget.email.replaceAll('.', '_').replaceAll('@', '_');
    String keyAbsen = "${emailEnc}_$today";

    try {
      final absensiRef = FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/absensi")
          .child(keyAbsen);
      final snapshot = await absensiRef.get();

      if (snapshot.exists) {
        Map dataLama = snapshot.value as Map;
        if (dataLama['jam_masuk'] != null && dataLama['jam_keluar'] == null) {
          await absensiRef.update({
            "jam_keluar": jamSekarang,
            "timestamp": ServerValue.timestamp,
          });

          if (mounted) {
            setState(() => _isLoading = false);
            _showSuccessDialog("Pulang Berhasil", jamSekarang);
          }
          return;
        } else {
          _showErrorDialog("Sudah Absen", "Data masuk & pulang sudah lengkap hari ini.");
          _scannerController.start();
          setState(() => _isLoading = false);
          return;
        }
      }

      DateTime waktuJadwal = DateFormat("HH:mm").parse(jamMulaiJadwal);
      DateTime waktuAbsen = DateFormat("HH:mm").parse(jamSekarang);
      bool isTelat = waktuAbsen.isAfter(waktuJadwal.add(const Duration(minutes: 1)));
      int menitTelat = isTelat ? waktuAbsen.difference(waktuJadwal).inMinutes : 0;

      // Di dalam fungsi _prosesSimpanAbsensi, ubah Map yang disimpan:
      await absensiRef.set({
        "nama": widget.nama,
        "email": widget.email.toLowerCase(),
        "tanggal": today,
        "jam_masuk": jamSekarang,
        "status": "Check-in", // Pastikan ini "Check-in" agar terbaca di Monitoring
        "keterangan": isTelat ? "Terlambat" : "Tepat Waktu",
        "is_telat": isTelat,
        "menit_telat": menitTelat,
        "jarak": _jarak.toInt(), // Simpan jarak agar muncul di Monitoring
        "shift": shiftName,
        "timestamp": ServerValue.timestamp,
      });

      _kirimNotifKeAtasan(
        shift: shiftName,
        jamDatang: jamSekarang,
        tanggal: today,
        menitTelat: menitTelat,
        jamSelesai: jamSelesaiJadwal,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        _showSuccessDialog(isTelat ? "Terlambat" : "Masuk Berhasil", jamSekarang);
      }
    } catch (e) {
      _scannerController.start();
      if (mounted) setState(() => _isLoading = false);
      _showErrorDialog("Gagal", "Gagal menyimpan absensi.");
    }
  }

  Future<void> _kirimNotifKeAtasan({
    required String shift,
    required String jamDatang,
    required String tanggal,
    required int menitTelat,
    required String jamSelesai,
  }) async {
    try {
      final snapshot = await FirebaseDatabase.instance.ref("users")
          .orderByChild("company_id").equalTo(widget.companyId).get();

      if (snapshot.exists) {
        Map users = snapshot.value as Map;
        users.forEach((key, value) {
          String role = value['role']?.toString().toLowerCase() ?? "";
          String? token = value['fcm_token'];

          if ((role == "manager" || role == "owner") && token != null) {
            NotificationHelper.sendNotification(
              targetToken: token,
              title: "Absensi Karyawan",
              body: "Nama: ${widget.nama}\nShift: $shift\nJam: $jamDatang\nStatus: ${menitTelat > 0 ? 'Telat $menitTelat mnt' : 'Tepat Waktu'}",
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Gagal kirim notif: $e");
    }
  }

  void _showErrorDialog(String title, String msg) {
    showDialog(context: context, builder: (c) => AlertDialog(
        title: Text(title, style: TextStyle(color: _statusRed, fontWeight: FontWeight.bold)),
        content: Text(msg),
        actions: [TextButton(onPressed: () {
          Navigator.pop(c);
          _scannerController.start(); // Aktifkan scanner lagi saat dialog ditutup
        }, child: const Text("TUTUP"))]
    ));
  }

  void _showSuccessDialog(String status, String jam) {
    showDialog(context: context, barrierDismissible: false, builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset('assets/animations/qr_scan.json', width: 120, height: 120, repeat: false),
          Text(status, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text("Pukul $jam WIB", style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
      actions: [
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () { Navigator.pop(c); Navigator.pop(context); },
          style: ElevatedButton.styleFrom(backgroundColor: _elegantBlack, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text("SELESAI"),
        ))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
          title: const Text("Scan Kehadiran", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _whiteCard, foregroundColor: _elegantBlack, elevation: 0
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(16), margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: _whiteCard, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _diDalamArea ? _statusGreen.withValues(alpha: 0.1) : _statusRed.withValues(alpha: 0.1))
          ),
          child: Row(children: [
            Icon(_diDalamArea ? Icons.check_circle : Icons.error_outline, color: _diDalamArea ? _statusGreen : _statusRed),
            const SizedBox(width: 12),
            Expanded(child: Text(_statusLokasi, style: TextStyle(fontWeight: FontWeight.bold, color: _diDalamArea ? _statusGreen : _statusRed))),
          ]),
        ),
        Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)]
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Stack(children: [
            MobileScanner(
              controller: _scannerController, // ✅ Gunakan variabel class-level
              onDetect: _onDetect,
            ),
            if (_isLoading) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
          ])),
        )),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: _whiteCard, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Jarak ke Kafe", style: TextStyle(color: Colors.grey)),
              Text("${_jarak.toInt()} m", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            if (_currentPosition != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  "Posisi Anda: ${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}",
                  style: const TextStyle(fontSize: 10, color: Colors.grey)
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Batas Radius", style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text("$_radiusMaksimal m", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _cekLokasiDanIzin,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("REFRESH LOKASI"),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _elegantBlack,
                  side: BorderSide(color: _borderGrey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
            )),
          ]),
        ),
      ]),
    );
  }
}