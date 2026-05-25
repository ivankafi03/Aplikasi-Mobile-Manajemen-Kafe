import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:table_calendar/table_calendar.dart'; // ✅ WAJIB ADA: package ini

import 'package:kafe_baru/absensi_page.dart';
import 'package:kafe_baru/admin_setup_page.dart';
import 'package:kafe_baru/kelola_info_page.dart';
import 'izin_page.dart';
import 'approval_page.dart';
import 'riwayat_page.dart';
import 'profil_page.dart';
import 'kelola_jadwal_page.dart';
import 'laporan_page.dart';
import 'karyawan_management_page.dart';
import 'chat_page.dart';
import 'notification_helper.dart';
import 'package:kafe_baru/aturan_gaji_page.dart';
import 'package:kafe_baru/form_tukar_shift.dart';
import 'package:kafe_baru/approval_tukar_page.dart';

class DashboardPage extends StatefulWidget {
  final String role;
  final String nama;
  final String email;
  final String uid;
  final String photoUrl;
  final String companyId;

  const DashboardPage({
    super.key,
    required this.role,
    required this.nama,
    required this.email,
    required this.uid,
    required this.photoUrl,
    required this.companyId,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Stream & Timer
  StreamSubscription? _notifSubscription;
  StreamSubscription? _managerNotifSubscription;
  StreamSubscription? _dailyAbsensiSubscription;
  StreamSubscription? _calendarSubscription;

  String _lastNotifSignature = "";
  String? _currentPhotoUrl;
  Timer? _qrTimer;
  Timer? _bannerTimer;

  final PageController _bannerController = PageController();
  final ValueNotifier<int> _secondsNotifier = ValueNotifier<int>(10);
  int _currentTabIndex = 0;
  int _currentBannerPage = 0;

  // --- LOGIKA KALENDER ---
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedCalendarDate = DateTime.now();
  Map<String, List<Map<String, dynamic>>> _myScheduleEvents = {};

  // --- PALET WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _white = const Color(0xFFFFFFFF);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _unselectedGrey = const Color(0xFF9E9E9E);
  final Color _borderGrey = const Color(0xFFEEEEEE);
  final Color _accentBlue = const Color(0xFF6495ED);
  final Color _shadowColor = const Color(0xFF2E3347).withValues(alpha: 0.08);

  @override
  void initState() {
    super.initState();
    _currentPhotoUrl = widget.photoUrl; // Set awal sesuai data login
    _listenToProfileChanges();
    _saveDeviceToken();
    _listenToInternalNotifications();
    _startBannerTimer();

    String role = widget.role.trim().toLowerCase();

    // Logic Role
    if (role == 'manager' || role == 'owner') {
      _listenToManagerNotifications();
      _listenToAttendanceRealtime();
    } else {
      _listenToAttendanceRealtime();
      _loadMySchedule();
    }

    if (role == 'admin' || role == 'admin_perusahaan') {
      _startQrAutoGenerator();
    }
  }

  void _listenToProfileChanges() {
    FirebaseDatabase.instance
        .ref("users/${widget.uid}/photo_url")
        .onValue
        .listen((event) {
      if (event.snapshot.exists && mounted) {
        setState(() {
          _currentPhotoUrl = event.snapshot.value.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    _managerNotifSubscription?.cancel();
    _dailyAbsensiSubscription?.cancel();
    _calendarSubscription?.cancel();
    _qrTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _secondsNotifier.dispose();
    super.dispose();
  }

  // --- 1. LOGIKA KALENDER KARYAWAN ---
  void _loadMySchedule() {
    _calendarSubscription?.cancel();

    _calendarSubscription = FirebaseDatabase.instance
        .ref("companies/${widget.companyId}/shifts")
        .orderByChild("email")
        .equalTo(widget.email)
        .onValue
        .listen((event) {

      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        Map<String, List<Map<String, dynamic>>> tempEvents = {};

        data.forEach((key, value) {
          final item = Map<String, dynamic>.from(value as Map);

          // ✅ PERUBAHAN PENTING: Simpan Key Shift
          item['key'] = key;

          String? tgl = item['tanggal'];
          if (tgl != null) {
            if (tempEvents[tgl] == null) tempEvents[tgl] = [];
            tempEvents[tgl]!.add(item);
          }
        });

        if (mounted) {
          setState(() {
            _myScheduleEvents = tempEvents;
          });
        }
      }
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    String tglStr = DateFormat('yyyy-MM-dd').format(day);
    return _myScheduleEvents[tglStr] ?? [];
  }

  // --- 2. LOGIKA REALTIME ABSENSI ---
  void _listenToAttendanceRealtime() {
    _dailyAbsensiSubscription?.cancel();

    String emailEnc = widget.email.replaceAll('.', '_').replaceAll('@', '_');
    String dateToday = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String keyHariIni = "${emailEnc}_$dateToday";

    DatabaseReference ref = FirebaseDatabase.instance
        .ref("companies/${widget.companyId}/absensi/$keyHariIni");

    _dailyAbsensiSubscription = ref.onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _prosesNotifikasiAbsen(event);
      }
    });
  }

  void _prosesNotifikasiAbsen(DatabaseEvent event) async {
    if (!mounted) return;

    final data = Map<String, dynamic>.from(event.snapshot.value as Map);

    String nama = data['nama'] ?? 'Karyawan';
    String? jamMasuk = data['jam_masuk'];
    String? jamKeluar = data['jam_keluar'];
    int timestamp = data['timestamp'] ?? 0;

    int now = DateTime.now().millisecondsSinceEpoch;

    // Filter Waktu (Max 45 detik lalu)
    if ((now - timestamp) > 45000) return;

    String tipe = "";
    String jam = "";

    if (jamKeluar != null && jamKeluar.isNotEmpty) {
      tipe = "Pulang";
      jam = jamKeluar;
    } else if (jamMasuk != null) {
      tipe = "Masuk";
      jam = jamMasuk;
    }

    String signature = "${tipe}_$jam";
    if (_lastNotifSignature == signature) return;
    _lastNotifSignature = signature;

    if (tipe.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Berhasil Absen $tipe ($jam)"),
        backgroundColor: tipe == "Masuk" ? Colors.green : Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
      ));

      try {
        final userSnap = await FirebaseDatabase.instance
            .ref("users/${widget.uid}/fcm_token").get();

        if (userSnap.exists) {
          await NotificationHelper.sendNotification(
              targetToken: userSnap.value.toString(),
              title: "Absensi Berhasil ✅",
              body: "Halo $nama, kamu berhasil absen $tipe pukul $jam."
          );
        }
      } catch (e) {
        debugPrint("❌ Gagal kirim notif: $e");
      }
    }
  }

  // --- FUNGSI HELPER LAIN ---
  void _startBannerTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_bannerController.hasClients) {
        _currentBannerPage++;
        _bannerController.animateToPage(
          _currentBannerPage % 3,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutQuart,
        );
      }
    });
  }

  void _startQrAutoGenerator() {
    _generateNewQRToken();
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsNotifier.value > 0) {
        _secondsNotifier.value--;
      } else {
        _secondsNotifier.value = 20;
        _generateNewQRToken();
      }
    });
  }

  void _generateNewQRToken() {
    String uniqueCode = "KAFE-${_generateRandomString(4)}-${_generateRandomString(4)}";
    FirebaseDatabase.instance.ref("companies/${widget.companyId}/settings/qr_code/token").set(uniqueCode);
  }

  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  void _saveDeviceToken() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      String? token = await messaging.getToken();
      if (token != null) {
        FirebaseDatabase.instance.ref("users/${widget.uid}").update({"fcm_token": token});
      }
    } catch (e) {
      debugPrint("Gagal simpan token: $e");
    }
  }

  void _listenToInternalNotifications() {
    _notifSubscription = FirebaseDatabase.instance.ref("companies/${widget.companyId}/notif_suara/${widget.uid}").onValue.listen((event) {
      if (event.snapshot.value != null && mounted) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['keterangan'] ?? 'Ada pembaruan'),
          backgroundColor: _elegantBlack,
          behavior: SnackBarBehavior.floating,
        ));
        event.snapshot.ref.remove();
      }
    });
  }

  void _listenToManagerNotifications() {
    _managerNotifSubscription = FirebaseDatabase.instance.ref("companies/${widget.companyId}/notif_manager/new_request").onValue.listen((event) {
      if (event.snapshot.value != null && mounted) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['pesan'] ?? 'Ada pengajuan izin baru'),
          backgroundColor: Colors.blueAccent,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'CEK', textColor: Colors.white, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ApprovalPage(companyId: widget.companyId)))),
        ));
        event.snapshot.ref.remove();
      }
    });
  }


  void _konfirmasiHapusAbsen(String key, String namaKaryawan) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (stfContext, setDialogState) {
            return AlertDialog(
              title: const Text("Hapus Absensi?"),
              content: isDeleting
                  ? const Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Menghapus data...")])
                  : Text("Apakah Anda yakin ingin menghapus data absensi $namaKaryawan hari ini?"),
              actions: isDeleting ? [] : [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("BATAL")),
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    setDialogState(() => isDeleting = true);
                    try {
                      await FirebaseDatabase.instance.ref("companies/${widget.companyId}/absensi/$key").remove();
                      if (!stfContext.mounted) return;
                      Navigator.pop(stfContext);
                      if (mounted) messenger.showSnackBar(const SnackBar(content: Text("Data berhasil dihapus"), backgroundColor: Colors.green));
                    } catch (e) {
                      if (!stfContext.mounted) return;
                      Navigator.pop(stfContext);
                    }
                  },
                  child: const Text("HAPUS", style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showQRProvider() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("QR Kode Absensi", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _secondsNotifier,
                builder: (context, seconds, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _bgScaffold,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: seconds < 4 ? Colors.red.withValues(alpha: 0.3) : Colors.transparent),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 16, color: seconds < 4 ? Colors.red : _elegantBlack),
                        const SizedBox(width: 8),
                        Text("Ganti dalam: $seconds dtk", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: seconds < 4 ? Colors.red : _elegantBlack, fontFamily: 'monospace')),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/settings/qr_code/token").onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                    String qrData = snapshot.data!.snapshot.value.toString();
                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _borderGrey), borderRadius: BorderRadius.circular(16)),
                          child: QrImageView(data: qrData, version: QrVersions.auto, size: 180),
                        ),
                        const SizedBox(height: 12),
                        Text("Token: $qrData", style: const TextStyle(fontSize: 9, color: Colors.grey, fontFamily: 'monospace')),
                      ],
                    );
                  }
                  return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator(color: Colors.black)));
                },
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () { _secondsNotifier.value = 20; _generateNewQRToken(); },
                icon: const Icon(Icons.refresh, size: 16, color: Colors.blue),
                label: const Text("Refresh Kode", style: TextStyle(fontSize: 12, color: Colors.blue)),
              ),
              const SizedBox(height: 12),
              Text(DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
        actions: [Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("TUTUP", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))))],
      ),
    );
  }

  // --- UI BUILDER ---
  @override
  Widget build(BuildContext context) {
    String roleLower = widget.role.trim().toLowerCase();
    bool isAdmin = roleLower == 'admin' || roleLower == 'admin_perusahaan';
    bool isKaryawan = roleLower == 'karyawan';

    bool showRiwayat = isKaryawan;

    int stackIndex = 0;
    if (_currentTabIndex == 0) stackIndex = 0;
    if (showRiwayat) {
      if (_currentTabIndex == 1) stackIndex = 1;
      if (_currentTabIndex == 3) stackIndex = 2;
    } else {
      if (_currentTabIndex == 1) stackIndex = 1;
      if (_currentTabIndex == 3) stackIndex = 2;
    }

    return Scaffold(
      backgroundColor: _bgScaffold,
      body: IndexedStack(
        index: stackIndex,
        children: [
          _buildDashboardHome(isKaryawan),
          if (showRiwayat)
            RiwayatPage(email: widget.email, companyId: widget.companyId)
          else
            LaporanPage(companyId: widget.companyId),
          ProfilPage(nama: widget.nama, email: widget.email, role: widget.role, uid: widget.uid),
        ],
      ),
      floatingActionButton: (isAdmin || isKaryawan)
          ? FloatingActionButton(
        onPressed: () {
          if (isAdmin) {
            _showQRProvider();
          } else if (isKaryawan) {
            Navigator.push(context, MaterialPageRoute(builder: (c) => AbsensiPage(nama: widget.nama, email: widget.email, companyId: widget.companyId)));
          }
        },
        backgroundColor: _elegantBlack, shape: const CircleBorder(), elevation: 4,
        child: Icon(isAdmin ? Icons.qr_code_2_rounded : Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
      ) : null,
      floatingActionButtonLocation: (isAdmin || isKaryawan) ? const LoweredFabLocation() : null,
      bottomNavigationBar: BottomAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 70, color: _white, elevation: 20,
        shape: (isAdmin || isKaryawan) ? const CircularNotchedRectangle() : null,
        notchMargin: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navIcon(0, Icons.grid_view_rounded, "Beranda"),
            if (showRiwayat)
              _navIcon(1, Icons.history_rounded, "Riwayat")
            else
              _navIcon(1, Icons.analytics_rounded, "Laporan"),
            if (isAdmin || isKaryawan) const SizedBox(width: 40),
            _navIcon(99, Icons.chat_bubble_outline_rounded, "Chat", isPush: true),
            _navIcon(3, Icons.person_outline_rounded, "Profil"),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardHome(bool isKaryawan) {
    return RefreshIndicator(
      color: _elegantBlack,
      backgroundColor: _white,
      onRefresh: () async {
        _saveDeviceToken();
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 25),
            _buildAnnouncementBanner(),
            const SizedBox(height: 25),
            if (isKaryawan) _buildWorkProgressCard() else _buildAdminStats(),

            // ✅ WIDGET BARU: INFO ATURAN GAJI (Hanya Karyawan)
            if (isKaryawan) ...[
              const SizedBox(height: 20),
              _buildSalaryRuleInfo(),
            ],

            const SizedBox(height: 30),
            const Text("Aktivitas Terkini", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildRecentActivityLog(),

            // ✅ KALENDER JADWAL KARYAWAN
            if (isKaryawan) ...[
              const SizedBox(height: 30),
              const Text("Jadwal Saya", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildEmployeeCalendar(),
            ],

            const SizedBox(height: 30),
            const Text("Layanan Utama", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildMenuGrid(),
          ],
        ),
      ),
    );
  }

  // ✅ WIDGET: INFO ATURAN GAJI (REALTIME)
  Widget _buildSalaryRuleInfo() {
    return StreamBuilder(
      stream: FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/settings/aturan_gaji")
          .onValue,
      builder: (context, snapshot) {
        // Default values
        int toleransi = 15;
        double dendaRingan = 1.0;
        double dendaSedang = 2.5;
        double dendaBerat = 5.0;

        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final data = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
          toleransi = data['toleransi'] ?? 15;
          dendaRingan = (data['denda_ringan'] ?? 1.0).toDouble();
          dendaSedang = (data['denda_sedang'] ?? 2.5).toDouble();
          dendaBerat = (data['denda_berat'] ?? 5.0).toDouble();
        }

        return InkWell(
          onTap: () {
            _showAturanDetailDialog(toleransi, dendaRingan, dendaSedang, dendaBerat);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Info Keterlambatan",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Toleransi Aman: $toleransi Menit",
                        style: TextStyle(color: Colors.orange[800], fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAturanDetailDialog(int toleransi, double r, double s, double b) {
    int rStart = toleransi + 1;
    int rEnd = toleransi + 15;
    int sStart = rEnd + 1;
    int sEnd = rEnd + 30;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Aturan Sanksi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Berikut adalah aturan potongan gaji jika Anda terlambat:", style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 15),
            _buildRowRule("✅ Aman", "0 - $toleransi menit", "0%", Colors.green),
            const Divider(),
            _buildRowRule("⚠️ Ringan", "$rStart - $rEnd menit", "$r%", Colors.orange),
            const Divider(),
            _buildRowRule("⚠️ Sedang", "$sStart - $sEnd menit", "$s%", Colors.deepOrange),
            const Divider(),
            _buildRowRule("⛔ Berat", "> $sEnd menit", "$b%", Colors.red),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("MENGERTI", style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildRowRule(String label, String range, String denda, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
              Text(range, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text("Potong $denda", style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
          )
        ],
      ),
    );
  }

  // ✅ WIDGET KALENDER BARU
  Widget _buildEmployeeCalendar() {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: _shadowColor, blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: _borderGrey),
      ),
      padding: const EdgeInsets.all(8),
      child: TableCalendar(
        firstDay: DateTime.now().subtract(const Duration(days: 30)),
        lastDay: DateTime.now().add(const Duration(days: 60)),
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
          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _elegantBlack),
          leftChevronIcon: const Icon(Icons.chevron_left),
          rightChevronIcon: const Icon(Icons.chevron_right),
        ),
        eventLoader: (day) => _getEventsForDay(day),
      ),
    );
  }

  void _showJadwalDetail(DateTime tanggal) {
    List<Map<String, dynamic>> events = _getEventsForDay(tanggal);
    String tglStr = DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(tanggal);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tglStr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: events.isEmpty
              ? const Text("Tidak ada jadwal shift.")
              : ListView.builder(
            shrinkWrap: true,
            itemCount: events.length,
            itemBuilder: (c, i) {
              final e = events[i];
              // Cek apakah ini jadwal saya
              bool isMyShift = e['email'] == widget.email;
              // Cek apakah jadwal belum lewat (Hari ini atau masa depan)
              bool isFuture = !tanggal.isBefore(DateTime.now().subtract(const Duration(days: 1)));

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule, color: Colors.blue),
                title: Text("${e['shift'] ?? 'Shift'} (${e['jam_mulai']} - ${e['jam_selesai']})"),
                subtitle: Text(e['jenis'] == 'khusus' ? 'Jadwal Khusus' : 'Jadwal Rutin'),

                // ✅ FITUR BARU: TOMBOL TUKAR SHIFT
                trailing: (isMyShift && isFuture && widget.role.toLowerCase() == 'karyawan')
                    ? IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded, color: Colors.orange),
                  tooltip: "Ajukan Tukar Shift",
                  onPressed: () {
                    Navigator.pop(ctx); // Tutup dialog dulu
                    Navigator.push(context, MaterialPageRoute(builder: (c) => FormTukarShiftPage(
                      companyId: widget.companyId,
                      myEmail: widget.email,
                      myName: widget.nama,
                      shiftData: e, // Kirim data shift ke halaman tukar
                    )));
                  },
                )
                    : null,
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup"))],
      ),
    );
  }

  // ... (WIDGET LAINNYA TETAP SAMA SEPERTI SEBELUMNYA) ...
  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    String greeting = hour < 12 ? "Selamat Pagi" : hour < 15 ? "Selamat Siang" : hour < 18 ? "Selamat Sore" : "Selamat Malam";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 10)],
                // ✅ GUNAKAN _currentPhotoUrl DI SINI
                image: (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty)
                    ? DecorationImage(image: NetworkImage(_currentPhotoUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: (_currentPhotoUrl == null || _currentPhotoUrl!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting, style: TextStyle(color: _unselectedGrey, fontSize: 12)),
              Text(widget.nama, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _buildAnnouncementBanner() {
    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/settings/announcements").onValue,
      builder: (context, snapshot) {
        List<Map<String, dynamic>> slides = [];
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final data = snapshot.data!.snapshot.value;
          if (data is Map) {
            data.forEach((k, v) => slides.add(Map<String, dynamic>.from(v)));
          }
        }

        if (slides.isEmpty) {
          slides = [{"title": "INFO KAFE:", "desc": "Selalu jaga kebersihan kafe kita bersama!"}];
        }

        return SizedBox(
          height: 105,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: slides.length,
            itemBuilder: (context, index) {
              final item = slides[index];
              final String title = item['title'] ?? "INFO:";
              final String desc = item['desc'] ?? "-";

              return InkWell(
                onTap: () {
                  Navigator.push(context, PageRouteBuilder(opaque: false, barrierDismissible: true, pageBuilder: (_, __, ___) => InfoDetailPage(title: title, desc: desc, indexTag: index)));
                },
                child: Hero(
                  tag: 'infoBanner_$index',
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.orange.shade400, Colors.deepOrange.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
                      ),
                      child: Row(children: [
                        const Icon(Icons.campaign_rounded, color: Colors.white, size: 30),
                        const SizedBox(width: 15),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                          const SizedBox(height: 4),
                          Text(desc, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ])),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAdminStats() {
    String hariIni = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return Row(children: [
      Expanded(child: StreamBuilder(
        stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/absensi").onValue,
        builder: (context, snapshot) {
          int countHadir = 0;
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            final data = snapshot.data!.snapshot.value;
            if (data is Map) {
              data.forEach((key, value) { if (value is Map && value['tanggal'] == hariIni) countHadir++; });
            }
          }
          return _statBox("Hadir", countHadir.toString().padLeft(2, '0'), Icons.how_to_reg_rounded, Colors.green);
        },
      )),
      const SizedBox(width: 16),
      Expanded(child: StreamBuilder(
        stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/izin_karyawan").onValue,
        builder: (context, snapshot) {
          int countIzin = 0;
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            final data = snapshot.data!.snapshot.value;
            if (data is Map) {
              data.forEach((key, value) { if (value is Map && value['tanggal'] == hariIni && (value['status'] == 'Disetujui' || value['status'] == 'approved')) countIzin++; });
            }
          }
          return _statBox("Izin", countIzin.toString().padLeft(2, '0'), Icons.event_busy_rounded, Colors.orange);
        },
      )),
    ]);
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 24)),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildWorkProgressCard() {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String emailEnc = widget.email.replaceAll('.', '_').replaceAll('@', '_');

    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/shifts/${emailEnc}_$today").onValue,
      builder: (context, shiftSnap) {
        return StreamBuilder(
            stream: FirebaseDatabase.instance
                .ref("companies/${widget.companyId}/absensi")
                .orderByChild("email")
                .equalTo(widget.email)
                .onValue,
            builder: (context, absenSnap) {

              String titleText = "JADWAL KOSONG";
              String sisaText = "Tidak Ada Jadwal";
              double progress = 0.0;

              Color cardColor = _white;
              Color titleColor = _unselectedGrey;
              Color bodyColor = _elegantBlack;
              Color progressTrackColor = _bgScaffold;
              Color progressValueColor = _accentBlue;
              IconData statusIcon = Icons.calendar_today_rounded;

              if (shiftSnap.hasData && shiftSnap.data!.snapshot.value != null) {
                final shiftData = shiftSnap.data!.snapshot.value as Map;

                titleText = "JADWAL HARI INI";
                sisaText = "Belum Absen Masuk";
                statusIcon = Icons.login_rounded;
                progressValueColor = Colors.orange.withValues(alpha: 0.5);

                if (absenSnap.hasData && absenSnap.data!.snapshot.value != null) {
                  final rawAbsen = absenSnap.data!.snapshot.value as Map;
                  rawAbsen.forEach((key, val) {
                    if (val['tanggal'] == today) {
                      String? jamMasuk = val['jam_masuk'];
                      String? jamKeluar = val['jam_keluar'];
                      String jamSelesaiJadwal = shiftData['jam_selesai'] ?? "16:00";

                      if (jamKeluar != null && jamKeluar.isNotEmpty) {
                        progress = 1.0;
                        titleText = "SHIFT SELESAI";
                        sisaText = "Sampai Jumpa Besok!";
                        statusIcon = Icons.check_circle_rounded;

                        cardColor = Colors.green;
                        titleColor = Colors.white70;
                        bodyColor = Colors.white;
                        progressTrackColor = Colors.white24;
                        progressValueColor = Colors.white;
                      }
                      else if (jamMasuk != null) {
                        titleText = "SEDANG BERTUGAS";
                        statusIcon = Icons.timer_rounded;

                        titleColor = Colors.white70;
                        bodyColor = Colors.white;
                        progressTrackColor = Colors.white24;
                        progressValueColor = Colors.white;

                        try {
                          DateTime now = DateTime.now();
                          DateFormat timeFormat = DateFormat("HH:mm");
                          DateTime start = timeFormat.parse(jamMasuk);
                          DateTime end = timeFormat.parse(jamSelesaiJadwal);

                          start = DateTime(now.year, now.month, now.day, start.hour, start.minute);
                          end = DateTime(now.year, now.month, now.day, end.hour, end.minute);

                          // Handle shift malam
                          if (end.isBefore(start)) end = end.add(const Duration(days: 1));

                          Duration totalDuration = end.difference(start);
                          Duration elapsed = now.difference(start);

                          if (totalDuration.inMinutes > 0) {
                            progress = elapsed.inMinutes / totalDuration.inMinutes;
                          }
                          if (progress > 1.0) progress = 1.0;
                          if (progress < 0.0) progress = 0.0;

                          Duration remaining = end.difference(now);

                          if (remaining.isNegative) {
                            sisaText = "Waktunya Pulang";
                            cardColor = Colors.redAccent;
                          } else {
                            sisaText = "Sisa: ${remaining.inHours}j ${remaining.inMinutes % 60}m";
                            cardColor = _accentBlue;
                          }
                        } catch (e) {
                          sisaText = "Error Waktu";
                        }
                      }
                    }
                  });
                }
              }

              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                        color: cardColor == _white ? _shadowColor : cardColor.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8)
                    )
                  ],
                  border: cardColor == _white ? Border.all(color: _bgScaffold, width: 1.5) : null,
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                            width: 64, height: 64,
                            child: CircularProgressIndicator(value: progress, strokeWidth: 6, backgroundColor: progressTrackColor, color: progressValueColor, strokeCap: StrokeCap.round)
                        ),
                        Icon(statusIcon, size: 26, color: bodyColor),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(titleText, style: TextStyle(color: titleColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            Text(sisaText, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: bodyColor)),
                          ]
                      ),
                    )
                  ],
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildRecentActivityLog() {
    String roleLower = widget.role.trim().toLowerCase();
    bool canDelete = roleLower == 'owner' || roleLower == 'manager' || roleLower == 'admin';

    DateTime now = DateTime.now();
    String hariIni = DateFormat('yyyy-MM-dd').format(now);
    String hariKemarin = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/absensi").orderByChild("timestamp").limitToLast(50).onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Belum ada aktivitas saat ini", style: TextStyle(fontSize: 12, color: Colors.grey))));
        }

        final rawData = snapshot.data!.snapshot.value;
        Map<dynamic, dynamic> dataMap = (rawData is Map) ? rawData : (rawData as List).asMap();
        List items = [];

        dataMap.forEach((key, val) {
          if (val is Map) {
            String tgl = val['tanggal'];
            String? jamKeluar = val['jam_keluar'];

            bool isToday = tgl == hariIni;
            bool isYesterdayStillWorking = (tgl == hariKemarin) && (jamKeluar == null || jamKeluar == "");

            if (isToday || isYesterdayStillWorking) {
              items.add({"key": key.toString(), ...val});
            }
          }
        });

        items.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

        if (items.isEmpty) {
          return Container(
            height: 100,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderGrey)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off_rounded, color: _unselectedGrey, size: 30),
                const SizedBox(height: 8),
                Text("Belum ada aktivitas shift aktif", style: TextStyle(color: _unselectedGrey, fontSize: 12)),
              ],
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(
            minHeight: 0,
            maxHeight: 350,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _borderGrey),
            boxShadow: [BoxShadow(color: _shadowColor, blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              bool isLate = item['is_telat'] == true;
              bool isStillWorking = item['jam_keluar'] == null || item['jam_keluar'] == "";
              String photoUrl = item['photo_url'] ?? "";
              String keyAbsen = item['key'];

              Color cardColor = isStillWorking ? Colors.blueAccent : Colors.green;

              return GestureDetector(
                onLongPress: canDelete ? () => _konfirmasiHapusAbsen(keyAbsen, item['nama']) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: cardColor.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white24,
                          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                          child: photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.white, size: 18) : null
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['nama'] ?? "User", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                            const SizedBox(height: 2),
                            item['tanggal'] == hariKemarin
                            // ✅ SUDAH DIPERBAIKI (PAKAI CONST)
                                ? Text("Shift Kemarin • Masuk: ${item['jam_masuk']}", style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.bold))
                                : Text(
                                isStillWorking ? "Masuk: ${item['jam_masuk']}" : "${item['jam_masuk']} - ${item['jam_keluar']}",
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11)
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isStillWorking ? Icons.timer : Icons.check_circle, color: Colors.white, size: 10),
                                const SizedBox(width: 4),
                                Text(isStillWorking ? "ON" : "DONE", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          if (isLate) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white, width: 1)),
                              child: const Text("TELAT", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                            ),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMenuGrid() {
    String roleLower = widget.role.trim().toLowerCase();
    List<Widget> menus = [];

    // --- MENU UNTUK ADMIN / MANAGER / OWNER ---
    if (roleLower == 'owner' || roleLower == 'manager' || roleLower == 'admin') {
      menus.add(_menuItem(Icons.groups_outlined, "Karyawan", Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (c) => KaryawanManagementPage(companyId: widget.companyId, myRole: widget.role)))));
      menus.add(_menuItem(Icons.campaign_rounded, "Kelola Info", Colors.deepOrange, () => Navigator.push(context, MaterialPageRoute(builder: (c) => KelolaInfoPage(companyId: widget.companyId)))));

      if (roleLower == 'owner' || roleLower == 'manager') {
        menus.add(_menuItem(Icons.calendar_month_outlined, "Kelola Jadwal", Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (c) => KelolaJadwalPage(companyId: widget.companyId)))));
        menus.add(_menuItem(Icons.fact_check_outlined, "Persetujuan", Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ApprovalPage(companyId: widget.companyId)))));

        // ✅ MENU BARU MANAGER: ACC Tukar Shift
        menus.add(_menuItem(Icons.swap_calls_rounded, "ACC Tukar Shift", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ApprovalTukarPage(companyId: widget.companyId, myEmail: widget.email, myRole: widget.role)))));
      }

      if (roleLower == 'owner') {
        menus.add(_menuItem(Icons.location_on_rounded, "Titik Lokasi", Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (c) => AdminSetupPage(companyId: widget.companyId)))));
        menus.add(_menuItem(Icons.monetization_on_rounded, "Aturan Gaji", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (c) => AturanGajiPage(companyId: widget.companyId)))));
      }
    }
    // --- MENU UNTUK KARYAWAN BIASA ---
    else {
      menus.add(_menuItem(Icons.edit_calendar_rounded, "Ajukan Izin", Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (c) => IzinPage(nama: widget.nama, email: widget.email, companyId: widget.companyId)))));

      // ✅ MENU BARU KARYAWAN: Inbox Tukar Shift
      menus.add(_menuItem(Icons.notifications_active_rounded, "Inbox Tukar", Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ApprovalTukarPage(companyId: widget.companyId, myEmail: widget.email, myRole: widget.role)))));
    }

    return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.4,
        children: menus
    );
  }

  Widget _menuItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _navIcon(int index, IconData icon, String label, {bool isPush = false}) {
    bool isActive = _currentTabIndex == index;
    return InkWell(
      onTap: () {
        if (isPush) {
          Navigator.push(context, MaterialPageRoute(builder: (c) => ChatPage(nama: widget.nama, email: widget.email, uid: widget.uid, role: widget.role, photoUrl: widget.photoUrl, companyId: widget.companyId)));
        } else { setState(() => _currentTabIndex = index); }
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: isActive ? _elegantBlack : _unselectedGrey, size: 24),
        Text(label, style: TextStyle(fontSize: 10, color: isActive ? _elegantBlack : _unselectedGrey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }
}

class LoweredFabLocation extends FloatingActionButtonLocation {
  const LoweredFabLocation();
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final Offset standard = FloatingActionButtonLocation.centerDocked.getOffset(scaffoldGeometry);
    return Offset(standard.dx, standard.dy + 20);
  }
}

class InfoDetailPage extends StatelessWidget {
  final String title;
  final String desc;
  final int indexTag;

  const InfoDetailPage({super.key, required this.title, required this.desc, required this.indexTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Hero(
                tag: 'infoBanner_$indexTag',
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.orange.shade400, Colors.deepOrange.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, spreadRadius: 5)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.campaign_rounded, color: Colors.white, size: 40),
                            const SizedBox(width: 15),
                            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1))),
                            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white70))
                          ],
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Colors.white24)),
                        Text(desc, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6), textAlign: TextAlign.left),
                        const SizedBox(height: 30),
                        Center(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.2), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)), onPressed: () => Navigator.pop(context), child: const Text("Tutup", style: TextStyle(fontWeight: FontWeight.bold)))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}