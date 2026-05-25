import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_database/firebase_database.dart';

class PengaturanCafePage extends StatefulWidget {
  // ✅ PERBAIKAN 1: Tambahkan parameter companyId agar tidak 'undefined'
  final String companyId;
  const PengaturanCafePage({super.key, required this.companyId});

  @override
  State<PengaturanCafePage> createState() => _PengaturanCafePageState();
}

class _PengaturanCafePageState extends State<PengaturanCafePage> {
  // --- PALET WARNA (WHITE ELEGANT THEME) ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _elegantBlack = const Color(0xFF212121);
  final Color _borderGrey = const Color(0xFFEEEEEE);

  // Lokasi Default (Akan diperbarui dari database jika ada)
  LatLng _lokasiTerpilih = const LatLng(-7.559336, 112.233546);
  bool _isLoading = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _ambilKoordinatLama();
  }

  // ✅ PERBAIKAN 2: Mengambil koordinat berdasarkan companyId
  void _ambilKoordinatLama() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/location")
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map;
        setState(() {
          _lokasiTerpilih = LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          );
        });
        // Pindahkan kamera peta ke lokasi lama
        _mapController.move(_lokasiTerpilih, 16.0);
      }
    } catch (e) {
      debugPrint("Gagal load koordinat: $e");
    }
  }

  void _recenterMap() {
    _mapController.move(_lokasiTerpilih, 16.0);
  }

  // ✅ PERBAIKAN 3: Simpan ke path perusahaan (Multi-tenant)
  void _simpanKeFirebase() async {
    setState(() => _isLoading = true);
    try {
      // Simpan di bawah folder perusahaan masing-masing
      await FirebaseDatabase.instance
          .ref("companies/${widget.companyId}/location")
          .set({
        "lat": _lokasiTerpilih.latitude,
        "lng": _lokasiTerpilih.longitude,
        "updated_at": ServerValue.timestamp,
        "updated_by": "Owner",
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Lokasi Kafe Berhasil Disimpan!", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Atur Lokasi Kafe", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: _textBlack)),
        backgroundColor: _whiteCard.withValues(alpha: 0.9),
        foregroundColor: _textBlack,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
        iconTheme: IconThemeData(color: _textBlack),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _lokasiTerpilih,
              initialZoom: 16.0,
              onTap: (tapPosition, point) {
                setState(() => _lokasiTerpilih = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ivan.kafe_sri_rahajoe',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _lokasiTerpilih,
                    width: 80, height: 80,
                    child: const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 50),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 120, right: 20,
            child: FloatingActionButton(
              mini: true, backgroundColor: _whiteCard, foregroundColor: _textBlack,
              onPressed: _recenterMap, child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              decoration: BoxDecoration(
                color: _whiteCard,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Lokasi Terpilih", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _bgScaffold, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderGrey)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCoordinateItem("Latitude", _lokasiTerpilih.latitude),
                        _buildCoordinateItem("Longitude", _lokasiTerpilih.longitude),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _simpanKeFirebase,
                      style: ElevatedButton.styleFrom(backgroundColor: _elegantBlack, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SIMPAN LOKASI"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateItem(String label, double value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: _textGrey)),
        Text(value.toStringAsFixed(6), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textBlack)),
      ],
    );
  }
}