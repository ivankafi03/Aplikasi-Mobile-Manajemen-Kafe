import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:async';

class KelolaJadwalPage extends StatefulWidget {
  final String companyId;
  const KelolaJadwalPage({super.key, required this.companyId});

  @override
  State<KelolaJadwalPage> createState() => _KelolaJadwalPageState();
}

class _KelolaJadwalPageState extends State<KelolaJadwalPage> with TickerProviderStateMixin {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final DatabaseReference _usersRef = FirebaseDatabase.instance.ref("users");

  // --- PALET WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _whiteSurface = const Color(0xFFF5F5F5);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  // --- PATH FIREBASE ---
  String get _companyPath => "companies/${widget.companyId}";

  // --- LOGIKA VARIABEL ---
  List<Map<String, dynamic>> _listKaryawan = [];
  bool _isLoading = false;
  bool _isLoadingKaryawan = true;

  String? _selectedKaryawanEmail;
  String? _selectedKaryawanNama;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _jamMulai = const TimeOfDay(hour: 08, minute: 00);
  TimeOfDay _jamSelesai = const TimeOfDay(hour: 16, minute: 00);
  String _namaShift = "Pagi";

  final List<String> _listHari = ['senin', 'selasa', 'rabu', 'kamis', 'jumat', 'sabtu', 'minggu'];
  final List<String> _listShift = ['Pagi', 'Siang', 'Malam'];

  final Map<String, List<Map<String, dynamic>>> _masterJadwalHarian = {};
  final Map<String, Map<String, TextEditingController>> _jamMulaiControllers = {};
  final Map<String, Map<String, TextEditingController>> _jamSelesaiControllers = {};

  late DateTime _focusedDay;
  DateTime? _selectedCalendarDate;
  Map<String, List<dynamic>> _events = {};
  late TabController _tabController;

  // ✅ TAMBAHAN: Variabel untuk Pantau Data Realtime
  StreamSubscription? _calendarStream;

  // ⚡ OPTIMASI: Polling untuk mencegah Infinite Loop
  Timer? _izinCheckTimer;
  bool _isProcessingIzin = false;
  List<Map<String, dynamic>> _riwayatPenggantian = [];

  String _encodeEmail(String email) {
    return email.replaceAll('.', '_').replaceAll('@', '_');
  }

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedCalendarDate = DateTime.now();
    _initMasterJadwalData();

    _loadAllData();
    _tabController = TabController(length: 3, vsync: this);

    _startPollingIzin();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEvents();
      _loadRiwayatPenggantian();
    });
  }

  @override
  void dispose() {
    _calendarStream?.cancel(); // ✅ Matikan pantauan realtime saat keluar halaman
    _izinCheckTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ⚡ PERBAIKAN: Gunakan Server-Side Filtering (processed == false)
  void _startPollingIzin() {
    _izinCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkPendingIzin();
    });
  }

  Future<void> _checkPendingIzin() async {
    if (_isProcessingIzin || !mounted) return;

    try {
      _isProcessingIzin = true;
      final snapshot = await _dbRef
          .child("$_companyPath/izin_karyawan")
          .orderByChild("processed")
          .equalTo(false) // ⬅️ Hanya ambil data baru
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map;
        for (var entry in data.entries) {
          final val = entry.value as Map;
          final status = (val['status'] ?? "").toString().toLowerCase();

          if (status == 'approved' || status == 'disetujui') {
            await _prosesPenggantianJadwal(entry.key.toString(), val);
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Polling Error: $e");
    } finally {
      _isProcessingIzin = false;
    }
  }

  // --- LOGIKA CORE ---
  Future<void> _loadAllData() async {
    await _ambilDataKaryawan();
    if (_listKaryawan.isNotEmpty) {
      await _bersihkanJadwalDariUserTerhapus();
    }
    await _loadMasterJadwal();
  }

  Future<void> _prosesPenggantianJadwal(String izinId, Map<dynamic, dynamic> izinData) async {
    try {
      final String email = (izinData['email_karyawan'] ?? '').toString();
      final String tgl = (izinData['tanggal'] ?? '').toString();

      if (email.isEmpty || tgl.isEmpty) {
        // Tandai processed agar tidak diulang meski data tidak lengkap
        await _dbRef.child("$_companyPath/izin_karyawan/$izinId").update({"processed": true});
        return;
      }

      String shiftKey = "${_encodeEmail(email)}_$tgl";
      final shiftRef = _dbRef.child("$_companyPath/shifts/$shiftKey");
      final shiftSnap = await shiftRef.get();

      if (shiftSnap.exists) {
        final sVal = Map<String, dynamic>.from(shiftSnap.value as Map);
        await shiftRef.remove();

        await _simpanRiwayatPenggantian({
          'id_shift': shiftKey,
          'email_asli': email,
          'nama_asli': izinData['nama_karyawan'] ?? 'Karyawan',
          'tanggal': tgl,
          'shift': sVal['nama_shift'] ?? sVal['shift'] ?? 'Shift',
          'jam_mulai': sVal['jam_mulai'] ?? '08:00',
          'jam_selesai': sVal['jam_selesai'] ?? '16:00',
          'waktu_proses': DateTime.now().toIso8601String(),
          'status': 'dihapus',
          'alasan': 'Izin disetujui otomatis',
        });
      }

      await _dbRef.child("$_companyPath/izin_karyawan/$izinId").update({
        "processed": true,
        "processed_at": ServerValue.timestamp,
      });

      _loadEvents(); // Refresh tampilan kalender
    } catch (e) {
      debugPrint("❌ Error Proses: $e");
    }
  }

  String _formatTanggalIndonesia(DateTime date) {
    return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
  }

  // --- INIT DATA ---
  void _initMasterJadwalData() {
    for (var hari in _listHari) {
      _masterJadwalHarian[hari] = [];
      _jamMulaiControllers[hari] = {};
      _jamSelesaiControllers[hari] = {};
    }
  }

  void _tambahKaryawanKeMaster(String hari) {
    setState(() {
      String uniqueId = '${DateTime.now().millisecondsSinceEpoch}';
      _masterJadwalHarian[hari]!.add({'id': uniqueId, 'email': null, 'nama': null, 'shift': 'Pagi'});
      _jamMulaiControllers[hari]![uniqueId] = TextEditingController(text: '08:00');
      _jamSelesaiControllers[hari]![uniqueId] = TextEditingController(text: '16:00');
    });
  }

  void _hapusKaryawanDariMaster(String hari, String id) {
    setState(() {
      _masterJadwalHarian[hari]!.removeWhere((item) => item['id'] == id);
      _jamMulaiControllers[hari]!.remove(id);
      _jamSelesaiControllers[hari]!.remove(id);
    });
  }

  void _updateKaryawanMaster(String hari, String id, String field, dynamic value) {
    setState(() {
      int index = _masterJadwalHarian[hari]!.indexWhere((item) => item['id'] == id);
      if (index != -1) {
        _masterJadwalHarian[hari]![index][field] = value;
      }
    });
  }

  Future<void> _ambilDataKaryawan() async {
    debugPrint("🔍 KelolaJadwal: Mencari karyawan untuk ID: ${widget.companyId}");
    setState(() => _isLoadingKaryawan = true);

    try {
      final snapshot = await _usersRef
          .orderByChild("company_id")
          .equalTo(widget.companyId)
          .get();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> data = snapshot.value as Map;
        List<Map<String, dynamic>> temp = [];

        data.forEach((key, value) {
          final userData = Map<String, dynamic>.from(value as Map);

          String role = (userData['role'] ?? '').toString().toLowerCase();
          bool isActive = userData['is_active'] ?? true;
          String name = userData['nama'] ?? 'Tanpa Nama';

          if (role == 'karyawan' && isActive) {
            temp.add({
              "email": userData['email'],
              "nama": name,
              "uid": key.toString(),
              "role": role,
            });
          }
        });

        if (mounted) {
          setState(() {
            _listKaryawan = temp;
            _isLoadingKaryawan = false;
          });
        }
      } else {
        debugPrint("⚠️ Tidak ada user ditemukan untuk ID: ${widget.companyId}");
        if (mounted) setState(() { _listKaryawan = []; _isLoadingKaryawan = false; });
      }
    } catch (e) {
      debugPrint("❌ Error Fetch Karyawan: $e");
      if (mounted) setState(() => _isLoadingKaryawan = false);
    }
  }

  Future<void> _bersihkanJadwalDariUserTerhapus() async {
    if (_listKaryawan.isEmpty) return;

    try {
      final emailsAktif = _listKaryawan.map((e) => e['email']?.toString()).toSet();
      int totalDibersihkan = 0;

      for (var hari in _listHari) {
        int sebelum = _masterJadwalHarian[hari]!.length;
        _masterJadwalHarian[hari]!.removeWhere((item) {
          final email = item['email'];
          return email != null && !emailsAktif.contains(email);
        });
        totalDibersihkan += sebelum - _masterJadwalHarian[hari]!.length;

        Set<String> validIds = _masterJadwalHarian[hari]!
            .where((e) => e['id'] != null)
            .map<String>((e) => e['id'].toString())
            .toSet();
        _jamMulaiControllers[hari]!.removeWhere((key, value) => !validIds.contains(key));
        _jamSelesaiControllers[hari]!.removeWhere((key, value) => !validIds.contains(key));
      }

      final masterRef = _dbRef.child("$_companyPath/master_jadwal");
      final masterSnap = await masterRef.get();

      if (masterSnap.exists) {
        Map data = masterSnap.value as Map;
        Map<String, dynamic> updatedData = {};

        data.forEach((hari, rawData) {
          List<dynamic> listKaryawanHari = [];
          if (rawData is List) {
            listKaryawanHari = rawData;
          } else if (rawData is Map) {
            listKaryawanHari = rawData.values.toList();
          }

          final cleanedList = listKaryawanHari.where((item) {
            if (item == null) return false;
            final email = (item as Map)['email']?.toString();
            return email != null && emailsAktif.contains(email);
          }).toList();

          updatedData[hari] = cleanedList;
        });
        await masterRef.set(updatedData);
      }

      if (totalDibersihkan > 0 && mounted) {
        debugPrint("✅ $totalDibersihkan data jadwal usang dibersihkan");
      }
    } catch (e) {
      debugPrint("❌ Error bersihkan jadwal: $e");
    }
  }

  Future<void> _loadMasterJadwal() async {
    try {
      final snapshot = await _dbRef.child("$_companyPath/master_jadwal").get();
      if (snapshot.exists) {
        Map data = snapshot.value as Map;

        for (var hari in _listHari) {
          if (data.containsKey(hari)) {
            var hariDataRaw = data[hari];
            List<dynamic> listKaryawanHari = [];

            if (hariDataRaw is List) {
              listKaryawanHari = hariDataRaw;
            } else if (hariDataRaw is Map) {
              listKaryawanHari = hariDataRaw.values.toList();
            }

            _masterJadwalHarian[hari]!.clear();
            _jamMulaiControllers[hari]!.clear();
            _jamSelesaiControllers[hari]!.clear();

            for (var karyawanData in listKaryawanHari) {
              if (karyawanData == null) continue;

              Map<dynamic, dynamic> item = karyawanData as Map;
              String id = '${DateTime.now().millisecondsSinceEpoch}_${item['email']}';

              _masterJadwalHarian[hari]!.add({
                'id': id,
                'email': item['email']?.toString(),
                'nama': item['nama_karyawan']?.toString(),
                'shift': item['shift']?.toString() ?? 'Pagi',
              });

              _jamMulaiControllers[hari]![id] = TextEditingController(text: item['jam_mulai'] ?? '08:00');
              _jamSelesaiControllers[hari]![id] = TextEditingController(text: item['jam_selesai'] ?? '16:00');
            }
          }
        }
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("❌ Error load master: $e");
    }
  }

  // --- REFRESH DATA METHOD ---
  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() {
      _listKaryawan = [];
      _isLoadingKaryawan = true;
    });

    await _loadAllData();

    if (mounted) {
      _showSnackBar("Data berhasil direfresh", _elegantBlack);
    }
  }

  Future<void> _refreshKalender() async {
    // ✅ Hapus 'await' dan loading state yang kompleks
    // Karena ini stream, pemanggilannya instan (tidak perlu ditunggu)
    _loadEvents();

    if (mounted) {
      _showSnackBar("Sinkronisasi ulang...", _elegantBlack);
    }
  }

  // --- DATE & TIME PICKER ---
  Future<void> _pilihJam(BuildContext context, bool isMulai, {required String hari, required String karyawanId}) async {
    TextEditingController? controller;
    if (isMulai) {
      controller = _jamMulaiControllers[hari]?[karyawanId];
    } else {
      controller = _jamSelesaiControllers[hari]?[karyawanId];
    }

    String currentTime = controller?.text ?? '08:00';
    List<String> parts = currentTime.split(':');
    TimeOfDay initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: _elegantBlack,
            onPrimary: Colors.white,
            surface: _whiteCard,
            onSurface: _textBlack,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        String formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        if (isMulai) {
          _jamMulaiControllers[hari]?[karyawanId]?.text = formatted;
        } else {
          _jamSelesaiControllers[hari]?[karyawanId]?.text = formatted;
        }
      });
    }
  }

  // --- ACTIONS ---
  Future<void> _simpanJadwalKhusus() async {
    if (_selectedKaryawanEmail == null) {
      _showSnackBar("Pilih karyawan dulu!", Colors.red);
      return;
    }
    setState(() => _isLoading = true);
    try {
      String tglFormat = DateFormat('yyyy-MM-dd').format(_selectedDate);
      String encodedEmail = _encodeEmail(_selectedKaryawanEmail!);
      String customKey = "${encodedEmail}_$tglFormat";

      await _dbRef
          .child("$_companyPath/shifts/$customKey")
          .set({
        "company_id": widget.companyId,
        "email": _selectedKaryawanEmail,
        "nama_karyawan": _selectedKaryawanNama,
        "tanggal": tglFormat,
        "jam_mulai": "${_jamMulai.hour.toString().padLeft(2, '0')}:${_jamMulai.minute.toString().padLeft(2, '0')}",
        "jam_selesai": "${_jamSelesai.hour.toString().padLeft(2, '0')}:${_jamSelesai.minute.toString().padLeft(2, '0')}",
        "nama_shift": _namaShift,
        "jenis": "khusus",
        "created_at": ServerValue.timestamp,
      });

      if (!context.mounted) return;
      _showSnackBar("Jadwal khusus tersimpan!", Colors.black);
      setState(() {
        _selectedKaryawanEmail = null;
        _selectedKaryawanNama = null;
        _isLoading = false;
      });

      _loadEvents(); // Refresh kalender
    } catch (e) {
      if (mounted) {
        _showSnackBar("Error: $e", Colors.red);
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _simpanMasterJadwal() async {
    setState(() => _isLoading = true);
    try {
      final ref = FirebaseDatabase.instance
          .ref("$_companyPath/master_jadwal");
      Map<String, dynamic> jadwalData = {};

      for (var hari in _listHari) {
        List<Map<String, dynamic>> dataHari = [];
        for (var karyawan in _masterJadwalHarian[hari]!) {
          if (karyawan['email'] == null) {
            _showSnackBar("Lengkapi data hari $hari!", Colors.orange);
            setState(() => _isLoading = false);
            return;
          }
          dataHari.add({
            'company_id': widget.companyId,
            'email': karyawan['email'],
            'nama_karyawan': karyawan['nama'],
            'shift': karyawan['shift'] ?? 'Pagi',
            'jam_mulai': _jamMulaiControllers[hari]?[karyawan['id']]?.text ?? '08:00',
            'jam_selesai': _jamSelesaiControllers[hari]?[karyawan['id']]?.text ?? '16:00',
            'updated_at': ServerValue.timestamp,
          });
        }
        jadwalData[hari] = dataHari;
      }
      await ref.set(jadwalData);
      if (!context.mounted) return;
      _showSnackBar("Master jadwal tersimpan!", _elegantBlack);
    } catch (e) {
      if (context.mounted) _showSnackBar("Error: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ MODIFIKASI: Menambahkan Loading Dialog dengan Animasi Titik Kuning
  Future<void> _generateJadwalBulanan() async {
    // 1. Tampilkan Dialog Loading dengan Animasi Titik Kuning
    showDialog(
      context: context,
      barrierDismissible: false, // User tidak bisa tutup paksa
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: _whiteCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Sedang Menyusun Jadwal",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 20),

                // 🔥 PANGGIL WIDGET ANIMASI TITIK KUNING DI SINI
                const LoadingTitikKuning(),

                const SizedBox(height: 16),
                Text(
                  "Mohon tunggu sebentar...",
                  style: TextStyle(fontSize: 12, color: _textGrey),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final master = await _dbRef.child("$_companyPath/master_jadwal").get();

      if (!master.exists) {
        if (mounted) Navigator.pop(context); // Tutup Loading
        _showSnackBar("Setel Master Jadwal dulu!", Colors.red);
        return;
      }

      Map masterData = master.value as Map;
      DateTime hariIni = DateTime.now();
      int jadwalDibuat = 0;

      // Loop 30 Hari
      for (int i = 0; i < 30; i++) {
        DateTime tglTarget = hariIni.add(Duration(days: i));
        String tglStr = DateFormat('yyyy-MM-dd').format(tglTarget);
        String namaHari = DateFormat('EEEE', 'id_ID').format(tglTarget).toLowerCase();

        if (masterData.containsKey(namaHari)) {
          var rawHariData = masterData[namaHari];
          List<dynamic> hariData = (rawHariData is List) ? rawHariData : (rawHariData as Map).values.toList();

          for (var d in hariData) {
            if (d == null) continue;
            String encodedEmail = _encodeEmail(d['email'] ?? '');
            String key = "${encodedEmail}_$tglStr";
            final existing = await _dbRef.child("$_companyPath/shifts/$key").get();

            if (!existing.exists) {
              await _dbRef.child("$_companyPath/shifts/$key").set({
                "company_id": widget.companyId,
                "email": d['email'],
                "nama_karyawan": d['nama_karyawan'] ?? "Karyawan",
                "shift": d['shift'] ?? 'Pagi',
                "tanggal": tglStr,
                "jam_mulai": d['jam_mulai'] ?? '08:00',
                "jam_selesai": d['jam_selesai'] ?? '16:00',
                "jenis": "rutin",
                "created_at": ServerValue.timestamp,
              });
              jadwalDibuat++;
            }
          }
        }
        // Jeda kecil agar animasi tetap jalan mulus
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (mounted) Navigator.pop(context); // ✅ TUTUP DIALOG OTOMATIS
      _showSnackBar("$jadwalDibuat jadwal baru berhasil dibuat!", Colors.green);
      _loadEvents();

    } catch (e) {
      if (mounted) Navigator.pop(context); // ✅ TUTUP DIALOG JIKA ERROR
      _showSnackBar("Error generate: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _simpanRiwayatPenggantian(Map<String, dynamic> data) async {
    await _dbRef
        .child("$_companyPath/riwayat_penggantian")
        .push().set({
      ...data,
      'company_id': widget.companyId,
      'created_at': ServerValue.timestamp
    });
    if (mounted) {
      setState(() => _riwayatPenggantian.insert(0, data));
    }
  }

  Future<void> _loadRiwayatPenggantian() async {
    try {
      final snapshot = await _dbRef
          .child("$_companyPath/riwayat_penggantian")
          .orderByChild("created_at")
          .limitToLast(50) // ⚡ BATASI DATA UNTUK MENCEGAH LAG
          .get();
      if (snapshot.exists) {
        Map data = snapshot.value as Map;
        List<Map<String, dynamic>> temp = [];
        data.forEach((key, value) => temp.add({'id': key, ...Map<String, dynamic>.from(value)}));
        temp.sort((a, b) => (b['waktu_proses'] ?? '').compareTo(a['waktu_proses'] ?? ''));
        if (mounted) {
          setState(() => _riwayatPenggantian = temp);
        }
      }
    } catch (e) {
      debugPrint("❌ Error riwayat: $e");
    }
  }

  // ✅ KODE BARU: Menggunakan Stream (.onValue)
  void _loadEvents() {
    // 1. Batalkan stream lama jika ada (biar gak numpuk)
    _calendarStream?.cancel();

    DateTime now = DateTime.now();
    // Ambil rentang data -30 hari sampai +60 hari
    String startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
    String endDate = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 60)));

    // 2. Gunakan .onValue.listen (Pantau Terus)
    _calendarStream = _dbRef
        .child("$_companyPath/shifts")
        .orderByChild("tanggal")
        .startAt(startDate)
        .endAt(endDate)
        .onValue
        .listen((event) {

      if (event.snapshot.exists) {
        Map data = event.snapshot.value as Map;
        Map<String, List<dynamic>> newEvents = {};

        data.forEach((key, value) {
          String? tanggal = value['tanggal'];
          if (tanggal != null) {
            if (!newEvents.containsKey(tanggal)) {
              newEvents[tanggal] = [];
            }
            newEvents[tanggal]!.add({
              'id': key,
              ...Map<String, dynamic>.from(value)
            });
          }
        });

        if (mounted) {
          setState(() => _events = newEvents);
        }
      } else {
        if (mounted) {
          setState(() => _events = {});
        }
      }
    });
  }

  // --- UI WIDGETS ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Kelola Jadwal", style: TextStyle(fontWeight: FontWeight.w600, color: _textBlack)),
        centerTitle: true,
        backgroundColor: _whiteCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textBlack),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: "Refresh data",
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: _whiteCard,
            child: TabBar(
              controller: _tabController,
              labelColor: _textBlack,
              unselectedLabelColor: _textGrey,
              indicatorColor: _elegantBlack,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'Khusus'),
                Tab(text: 'Master'),
                Tab(text: 'Kalender'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildJadwalKhususTab(),
          _buildMasterJadwalTab(),
          _buildKalenderJadwal(),
        ],
      ),
    );
  }

  Widget _buildJadwalKhususTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Input Jadwal Khusus", "Jadwal manual hari tertentu."),
          const SizedBox(height: 20),

          if (_isLoadingKaryawan)
            Center(child: CircularProgressIndicator(color: _elegantBlack))
          else if (_listKaryawan.isEmpty)
            _buildEmptyState()
          else
            _buildDropdownKaryawan(),
          const SizedBox(height: 16),
          _buildDatePicker(),
          const SizedBox(height: 16),
          _buildDropdown("Pilih Shift", _namaShift, _listShift.map((s) => DropdownMenuItem<String>(value: s, child: Text(s, style: TextStyle(color: _textBlack)))).toList(), (val) => setState(() => _namaShift = val!)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildTimePicker("Mulai", _jamMulai, (t) => setState(() => _jamMulai = t))),
              const SizedBox(width: 12),
              Expanded(child: _buildTimePicker("Selesai", _jamSelesai, (t) => setState(() => _jamSelesai = t))),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _simpanJadwalKhusus,
              icon: const Icon(Icons.save, size: 18),
              label: Text(_isLoading ? "Menyimpan..." : "SIMPAN JADWAL"),
              style: ElevatedButton.styleFrom(
                backgroundColor: _elegantBlack,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownKaryawan() {
    String? validValue = _listKaryawan.any((k) => k['email'] == _selectedKaryawanEmail)
        ? _selectedKaryawanEmail
        : null;

    return DropdownButtonFormField<String>(
      key: ValueKey(validValue),
      initialValue: validValue,
      decoration: InputDecoration(
        labelText: "Pilih Karyawan",
        filled: true,
        fillColor: _whiteCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      hint: const Text("Pilih Karyawan"),
      items: _listKaryawan.map((k) {
        return DropdownMenuItem<String>(
          value: k['email'],
          child: Text("${k['nama']} (${k['role'].toString().toUpperCase()})"),
        );
      }).toList(),
      onChanged: (val) {
        setState(() {
          _selectedKaryawanEmail = val;
          _selectedKaryawanNama = _listKaryawan.firstWhere((e) => e['email'] == val)['nama'];
        });
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1), // ✅ PERBAIKAN: withValues
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(height: 8),
          Text("Karyawan tidak ditemukan untuk ID: ${widget.companyId}",
              style: const TextStyle(fontSize: 12, color: Colors.orange),
              textAlign: TextAlign.center
          ),
          TextButton(
            onPressed: _ambilDataKaryawan,
            child: const Text("Coba Lagi"),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterJadwalTab() {
    if (_isLoadingKaryawan) return Center(child: CircularProgressIndicator(color: _elegantBlack));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ..._listHari.map((hari) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _whiteCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderGrey),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _whiteSurface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(hari.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: _textBlack)),
                        IconButton(
                          icon: const Icon(Icons.add_circle),
                          onPressed: () => _tambahKaryawanKeMaster(hari),
                        )
                      ],
                    ),
                  ),
                  if (_masterJadwalHarian[hari]!.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text("Belum ada jadwal", style: TextStyle(color: _textGrey))
                    ),
                  ..._masterJadwalHarian[hari]!.map((karyawan) {
                    String id = karyawan['id'];
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildSimpleDropdown(karyawan['email'], "Pilih Karyawan", [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text("-- Pilih Karyawan --", style: TextStyle(color: Colors.grey)),
                                  ),
                                  ..._listKaryawan.map((k) {
                                    return DropdownMenuItem<String>(
                                        value: k['email'],
                                        child: Text("${k['nama']} (${k['role']})", overflow: TextOverflow.ellipsis)
                                    );
                                  }),
                                ], (val) {
                                  if (val != null) {
                                    try {
                                      final sel = _listKaryawan.firstWhere((k) => k['email'] == val);
                                      _updateKaryawanMaster(hari, id, 'email', val);
                                      _updateKaryawanMaster(hari, id, 'nama', sel['nama']);
                                    } catch (e) {
                                      _updateKaryawanMaster(hari, id, 'email', val);
                                    }
                                  }
                                }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () => _hapusKaryawanDariMaster(hari, id),
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: _buildSimpleDropdown(
                                      karyawan['shift'],
                                      "Shift",
                                      _listShift.map((s) => DropdownMenuItem<String>(
                                          value: s,
                                          child: Text(s)
                                      )).toList(),
                                          (val) => _updateKaryawanMaster(hari, id, 'shift', val)
                                  )
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: _buildCompactTime(hari, id, true)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildCompactTime(hari, id, false)),
                            ],
                          ),
                          const Divider(),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _simpanMasterJadwal,
              icon: const Icon(Icons.save_as, size: 18),
              label: const Text("SIMPAN MASTER MINGGUAN"),
              style: ElevatedButton.styleFrom(
                backgroundColor: _elegantBlack,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildKalenderJadwal() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _whiteCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderGrey),
              // ✅ PERBAIKAN: Ganti withOpacity dengan withValues
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text("Generate Jadwal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textBlack)),
                const SizedBox(height: 8),
                Text(
                    "Buat jadwal otomatis 30 hari ke depan berdasarkan Master Jadwal.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _textGrey)
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _generateJadwalBulanan,
                    icon: const Icon(Icons.autorenew),
                    label: const Text("GENERATE SEKARANG"),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _elegantBlack),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),

          Container(
            decoration: BoxDecoration(
                color: _whiteCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderGrey)
            ),
            padding: const EdgeInsets.all(8),
            child: TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 30)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedCalendarDate, day),
              onDaySelected: (selectedDay, focusedDay) {
                if (!isSameDay(_selectedCalendarDate, selectedDay)) {
                  setState(() {
                    _selectedCalendarDate = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  _showJadwalDetail(selectedDay);
                }
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(color: _elegantBlack, shape: BoxShape.circle),
                todayDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _elegantBlack),
                ),
                todayTextStyle: TextStyle(color: _elegantBlack, fontWeight: FontWeight.bold),
                markerDecoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                markersAutoAligned: true,
                markerSize: 6,
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textBlack),
                leftChevronIcon: const Icon(Icons.chevron_left),
                rightChevronIcon: const Icon(Icons.chevron_right),
              ),
              eventLoader: (day) {
                String tglStr = DateFormat('yyyy-MM-dd').format(day);
                return _events[tglStr] ?? [];
              },
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _refreshKalender,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Refresh Kalender"),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _borderGrey),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _showRiwayatPenggantian,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textGrey,
                    side: BorderSide(color: _borderGrey),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Lihat Riwayat"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showJadwalDetail(DateTime tanggal) {
    String tglStr = DateFormat('yyyy-MM-dd').format(tanggal);
    List<dynamic> jadwalHariIni = _events[tglStr] ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_formatTanggalIndonesia(tanggal)),
        content: SizedBox(
          width: double.maxFinite,
          child: jadwalHariIni.isEmpty
              ? const Text("Tidak ada jadwal.")
              : ListView.builder(
            shrinkWrap: true,
            itemCount: jadwalHariIni.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(jadwalHariIni[i]['nama_karyawan'] ?? 'User'),
              subtitle: Text(
                  "${jadwalHariIni[i]['shift'] ?? jadwalHariIni[i]['nama_shift'] ?? 'Pagi'} "
                      "(${jadwalHariIni[i]['jam_mulai'] ?? '--:--'} - ${jadwalHariIni[i]['jam_selesai'] ?? '--:--'})"
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Tutup"),
          ),
        ],
      ),
    );
  }

  // --- WIDGET HELPER LAINNYA ---
  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textBlack)),
        Text(subtitle, style: TextStyle(fontSize: 12, color: _textGrey)),
      ],
    );
  }

  Widget _buildDropdown(String label, String? value, List<DropdownMenuItem<String>> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textBlack)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: _whiteCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderGrey)
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down),
              items: items,
              onChanged: onChanged,
              dropdownColor: _whiteCard,
              style: TextStyle(color: _textBlack),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleDropdown(dynamic value, String hint, List<DropdownMenuItem<dynamic>> items, Function(dynamic) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: _whiteSurface,
          borderRadius: BorderRadius.circular(8)
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<dynamic>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: items,
          onChanged: onChanged,
          style: TextStyle(fontSize: 13, color: _textBlack),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime.now(),
          lastDate: DateTime(2100),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: _elegantBlack,
                onPrimary: Colors.white,
                onSurface: _textBlack,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          setState(() => _selectedDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _whiteCard,
          border: Border.all(color: _borderGrey),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
                DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate),
                style: TextStyle(color: _textBlack)
            ),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(String label, TimeOfDay time, Function(TimeOfDay) onPicked) {
    return InkWell(
      onTap: () async {
        final TimeOfDay? picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: _elegantBlack,
                onPrimary: Colors.white,
                onSurface: _textBlack,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _whiteCard,
          border: Border.all(color: _borderGrey),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: _textGrey)),
            Text(time.format(context), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textBlack)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTime(String hari, String id, bool isMulai) {
    var controller = isMulai ? _jamMulaiControllers[hari]![id] : _jamSelesaiControllers[hari]![id];
    return TextField(
      controller: controller,
      readOnly: true,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
        filled: true,
        fillColor: _whiteSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      onTap: () => _pilihJam(context, isMulai, hari: hari, karyawanId: id),
    );
  }

  void _showRiwayatPenggantian() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _whiteCard,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Riwayat Penggantian", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _textBlack)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _riwayatPenggantian.isEmpty
                  ? Center(child: Text("Belum ada riwayat", style: TextStyle(color: _textGrey)))
                  : ListView.builder(
                itemCount: _riwayatPenggantian.length,
                itemBuilder: (context, index) {
                  var r = _riwayatPenggantian[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _whiteSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${r['nama_asli'] ?? 'Karyawan'}",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              DateFormat('dd/MM HH:mm').format(
                                  DateTime.parse(r['waktu_proses'] ?? DateTime.now().toIso8601String())
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${r['tanggal']} • ${r['shift'] ?? 'Shift'} (${r['jam_mulai'] ?? '--:--'} - ${r['jam_selesai'] ?? '--:--'})",
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r['alasan'] ?? 'Izin disetujui',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
// ✅ WIDGET ANIMASI: Titik Kuning Muncul Satu per Satu
class LoadingTitikKuning extends StatefulWidget {
  const LoadingTitikKuning({super.key});

  @override
  State<LoadingTitikKuning> createState() => _LoadingTitikKuningState();
}

class _LoadingTitikKuningState extends State<LoadingTitikKuning> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    // Animasi berulang setiap 1.5 detik
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(() {
      // Mengubah jumlah titik: 0 -> 1 -> 2 -> 3 -> 0
      setState(() {
        _dotCount = (_controller.value * 4).floor() % 4;
      });
    })
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            // Logic Warna: Jika index < dotCount, warnanya kuning, jika tidak abu-abu
            color: index < _dotCount
                ? Colors.amber[700]
                : Colors.grey[300],
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}