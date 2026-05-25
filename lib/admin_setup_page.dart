import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

class AdminSetupPage extends StatefulWidget {
  final String companyId; // ID Kafe unik
  const AdminSetupPage({super.key, required this.companyId});

  @override
  State<AdminSetupPage> createState() => _AdminSetupPageState();
}

class _AdminSetupPageState extends State<AdminSetupPage> {
  bool _isLoading = false;

  // Path database yang terisolasi per kafe
  DatabaseReference get _dbRef => FirebaseDatabase.instance.ref("companies/${widget.companyId}/location");

  final TextEditingController _radiusController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  String _locationStatus = "Siap mengambil lokasi...";

  // --- PALET WARNA (Sudah digunakan di bawah agar tidak ada warning) ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _whiteSurface = const Color(0xFFF5F5F5);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _loadExistingConfig() async {
    try {
      final snapshot = await _dbRef.get();
      if (snapshot.exists) {
        final data = snapshot.value;
        if (data is Map) {
          setState(() {
            _radiusController.text = data['radius']?.toString() ?? "50";
            _latitudeController.text = data['lat']?.toString() ?? "";
            _longitudeController.text = data['lng']?.toString() ?? "";
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal load config: $e");
    }
  }

  void _getCurrentLocation() async {
    setState(() => _locationStatus = "Mencari satelit GPS...");
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationStatus = "Izin lokasi ditolak");
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;

      setState(() {
        _locationStatus = "Lokasi Berhasil Didapatkan";
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });
    } catch (e) {
      setState(() => _locationStatus = "Gagal: Pastikan GPS Aktif");
    }
  }

  void _saveLocationConfig() async {
    if (_latitudeController.text.isEmpty || _longitudeController.text.isEmpty) {
      _showSnackBar("Data lokasi belum lengkap!", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      double lat = double.parse(_latitudeController.text);
      double lng = double.parse(_longitudeController.text);
      int radius = int.tryParse(_radiusController.text) ?? 50;

      await _dbRef.set({
        "lat": lat,
        "lng": lng,
        "radius": radius,
        "updated_at": ServerValue.timestamp,
      });

      if (!mounted) return;
      _showSnackBar("Pengaturan Lokasi Tersimpan!");
    } catch (e) {
      _showSnackBar("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red[800] : _elegantBlack,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Titik Lokasi Kafe", style: TextStyle(color: _textBlack, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: _whiteCard,
        elevation: 0,
        iconTheme: IconThemeData(color: _textBlack),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildLocationSection(),
            const SizedBox(height: 24),
            _buildGuideCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      decoration: BoxDecoration(
        color: _whiteCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderGrey),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Koordinat GPS Kafe", style: TextStyle(fontWeight: FontWeight.bold, color: _textBlack)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _getCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: const Text("AMBIL LOKASI SAYA SEKARANG"),
              style: ElevatedButton.styleFrom(backgroundColor: _whiteSurface, foregroundColor: _textBlack),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(_locationStatus, style: TextStyle(fontSize: 12, color: _locationStatus.contains("Berhasil") ? Colors.green : _textGrey))),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildTextField(_latitudeController, "Latitude")),
              const SizedBox(width: 12),
              Expanded(child: _buildTextField(_longitudeController, "Longitude")),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(_radiusController, "Radius Absensi (Meter)", isNumber: true),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveLocationConfig,
              style: ElevatedButton.styleFrom(backgroundColor: _elegantBlack, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("SIMPAN LOKASI KAFE"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: _textBlack),
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(color: _textGrey),
        filled: true, fillColor: _whiteSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildGuideCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _whiteSurface, borderRadius: BorderRadius.circular(12)),
      child: Text(
        "Gunakan koordinat ini sebagai pusat absensi. Karyawan hanya bisa absen di dalam radius tersebut.",
        style: TextStyle(fontSize: 12, color: _textGrey, height: 1.5),
        textAlign: TextAlign.center,
      ),
    );
  }
}