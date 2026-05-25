import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class KelolaInfoPage extends StatefulWidget {
  final String companyId;

  const KelolaInfoPage({super.key, required this.companyId});

  @override
  State<KelolaInfoPage> createState() => _KelolaInfoPageState();
}

class _KelolaInfoPageState extends State<KelolaInfoPage> {
  late DatabaseReference _dbRef;
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  // --- PALET WARNA ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteCard = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _cardColor = const Color(0xFFFF7043); // ✅ ORANYE (Warna Utama Info)
  final Color _elegantBlack = const Color(0xFF212121);

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instance.ref("companies/${widget.companyId}/settings/announcements");
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _showForm([String? id, String? oldTitle, String? oldDesc]) {
    if (id != null) {
      _titleController.text = oldTitle!;
      _descController.text = oldDesc!;
    } else {
      _titleController.clear();
      _descController.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _whiteCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              id == null ? "Buat Info Baru" : "Edit Info",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textBlack),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: "Judul (Contoh: LIBUR LEBARAN)",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: _bgScaffold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Keterangan Info",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: _bgScaffold,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_titleController.text.isEmpty) return;

                  if (id == null) {
                    _dbRef.push().set({"title": _titleController.text, "desc": _descController.text});
                  } else {
                    _dbRef.child(id).update({"title": _titleController.text, "desc": _descController.text});
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _elegantBlack,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text("SIMPAN", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: AppBar(
        title: Text("Kelola Banner Info", style: TextStyle(fontWeight: FontWeight.w600, color: _textBlack)),
        centerTitle: true,
        backgroundColor: _whiteCard,
        elevation: 0,
        iconTheme: IconThemeData(color: _textBlack),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: _elegantBlack,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      // ... (kode atas tetap sama)

      body: StreamBuilder(
        stream: _dbRef.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ PERBAIKAN 1: withValues
                  Icon(Icons.campaign_outlined, size: 80, color: Colors.grey.withValues(alpha: 0.3)),
                  const SizedBox(height: 10),
                  const Text("Belum ada info aktif", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final rawData = snapshot.data!.snapshot.value;
          Map<dynamic, dynamic> data = {};
          if (rawData is Map) {
            data = rawData;
          } else if (rawData is List) {
            data = rawData.asMap();
          }

          List items = [];
          data.forEach((k, v) => items.add({"id": k.toString(), ...v}));

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    // ✅ PERBAIKAN 2: withValues
                    BoxShadow(color: _cardColor.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 4))
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      // ✅ PERBAIKAN 3: withValues
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 24),
                  ),
                  title: Text(
                    item['title'] ?? "",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item['desc'] ?? "",
                      // ✅ PERBAIKAN 4: withValues
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: Colors.white),
                        onPressed: () => _showForm(item['id'], item['title'], item['desc']),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: Colors.white),
                        onPressed: () => _dbRef.child(item['id']).remove(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
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