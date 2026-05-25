import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Import helper kamu (Pastikan file ini ada)
import 'notification_helper.dart';

final supabase = Supabase.instance.client;

class ChatPage extends StatefulWidget {
  final String nama;
  final String email;
  final String uid;
  final String role;
  final String photoUrl;
  final String companyId;

  const ChatPage({
    super.key,
    required this.nama,
    required this.email,
    required this.uid,
    required this.role,
    required this.photoUrl,
    required this.companyId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSearching = false;
  bool _isUploading = false;
  String _searchQuery = "";
  Map<String, String> _userPhotos = {};

  // --- DESIGN SYSTEM ---
  final Color _bgScaffold = const Color(0xFFF8F9FA);
  final Color _whiteSurface = const Color(0xFFFFFFFF);
  final Color _inputBg = const Color(0xFFF5F5F5); // Abu muda untuk kotak ketik
  final Color _myChatBubble = const Color(0xFFE65100);
  final Color _otherChatBubble = const Color(0xFFFFFFFF);
  final Color _textBlack = const Color(0xFF1A1A1A);
  final Color _textGrey = const Color(0xFF757575);
  final Color _borderGrey = const Color(0xFFEEEEEE);
  final Color _accentOrange = const Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null);
    _loadAllUserPhotos();
    _updateLastRead();
  }

  // --- LOGIC FUNCTIONS ---

  void _loadAllUserPhotos() {
    FirebaseDatabase.instance
        .ref("users")
        .orderByChild("company_id")
        .equalTo(widget.companyId)
        .onValue
        .listen((event) {
      if (event.snapshot.exists) {
        Map<String, String> tempMap = {};
        Map<dynamic, dynamic> values = event.snapshot.value as Map;
        values.forEach((key, value) {
          if (value is Map) {
            final email = value['email']?.toString();
            final photo = value['photo_url']?.toString();
            if (email != null && photo != null) {
              tempMap[email] = photo;
            }
          }
        });
        if (mounted) setState(() => _userPhotos = tempMap);
      }
    });
  }

  void _updateLastRead() {
    FirebaseDatabase.instance
        .ref("users/${widget.uid}/last_chat_read")
        .set(ServerValue.timestamp);
  }

  void _scrollToBottom() {
    // Beri sedikit jeda agar layout selesai dirender dulu
    if (_scrollController.hasClients) {
      // Jika jarak scroll sangat jauh, langsung lompat (jump),
      // jika dekat baru animasi. Ini biar user ga pusing liat scroll panjang.
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels > 500) {
        _scrollController.jumpTo(position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _kirimPesan() {
    if (_messageController.text.trim().isEmpty) return;
    _pushToFirebase(type: 'text', content: _messageController.text.trim());
    _messageController.clear();
  }

  Future<void> _pilihDanKirimGambar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image != null) {
      setState(() => _isUploading = true);
      try {
        File file = File(image.path);
        String fileName = "chat_${DateTime.now().millisecondsSinceEpoch}.jpg";

        await supabase.storage.from('avatars').upload('chat/$fileName', file);
        final String url = supabase.storage.from('avatars').getPublicUrl('chat/$fileName');

        _pushToFirebase(type: 'image', content: url);
      } catch (e) {
        _showSnackBar("Gagal mengupload gambar: $e", isError: true);
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  void _pushToFirebase({required String type, required String content}) {
    String currentPhoto = widget.photoUrl;

    FirebaseDatabase.instance.ref("companies/${widget.companyId}/messages/group_chat").push().set({
      "nama": widget.nama,
      "email": widget.email,
      "photo_url": currentPhoto,
      "type": type,
      "pesan": content,
      "timestamp": ServerValue.timestamp,
    });

    _updateLastRead();
    _broadcastNotif(content, type);
  }

  void _broadcastNotif(String msg, String type) async {
    String body = type == 'image' ? "📷 Mengirim foto" : msg;
    DataSnapshot snap = await FirebaseDatabase.instance.ref("users")
        .orderByChild("company_id")
        .equalTo(widget.companyId)
        .get();

    if (snap.exists) {
      Map data = snap.value as Map;
      data.forEach((key, val) {
        if (val['email'] != widget.email && val['fcm_token'] != null) {
          NotificationHelper.sendNotification(
            targetToken: val['fcm_token'],
            title: widget.nama,
            body: body,
            senderId: widget.uid, // 3. WAJIB kirim UID kamu di sini
          );
        }
      });
    }
  }

  void _hapusPesan(String key, String senderEmail) {
    bool canDelete = widget.email == senderEmail ||
        ['owner', 'manager', 'admin'].contains(widget.role.toLowerCase());

    if (!canDelete) {
      _showSnackBar("Hanya bisa menghapus pesan sendiri.");
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Hapus Pesan?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text("Pesan akan dihapus untuk semua orang."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              FirebaseDatabase.instance.ref("companies/${widget.companyId}/messages/group_chat/$key").remove();
              Navigator.pop(ctx);
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- UI WIDGETS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildChatStream()),
          if (_isUploading) _buildUploadingIndicator(),
          _buildInputArea(), // Ini yang sudah diperbaiki
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _whiteSurface,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: _textBlack, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: _isSearching
          ? TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(hintText: "Cari pesan...", border: InputBorder.none),
        onChanged: (v) => setState(() => _searchQuery = v),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Grup Koordinasi", style: TextStyle(color: _textBlack, fontSize: 16, fontWeight: FontWeight.bold)),
          Text("Tim Kerja Aktif", style: TextStyle(color: _textGrey, fontSize: 11)),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search, color: _textBlack),
          onPressed: () => setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) _searchQuery = "";
          }),
        )
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: _borderGrey, height: 1),
      ),
    );
  }

  Widget _buildChatStream() {
    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref("companies/${widget.companyId}/messages/group_chat").onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return _buildEmptyState();
        }

        final rawValue = snapshot.data!.snapshot.value;
        Map<dynamic, dynamic> data = {};
        if (rawValue is Map) {
          data = rawValue;
        } else if (rawValue is List) {
          data = rawValue.asMap();
        }
        List items = [];
        data.forEach((key, val) {
          if (_searchQuery.isEmpty || val['pesan'].toString().toLowerCase().contains(_searchQuery.toLowerCase())) {
            items.add({"key": key, ...val});
          }
        });

        items.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            bool isMe = item['email'] == widget.email;

            bool showDate = false;
            DateTime currentDay = DateTime.fromMillisecondsSinceEpoch(item['timestamp']);
            if (index == 0) {
              showDate = true;
            } else {
              DateTime prevDay = DateTime.fromMillisecondsSinceEpoch(items[index-1]['timestamp']);
              if (currentDay.day != prevDay.day) showDate = true;
            }

            return Column(
              children: [
                if (showDate) _buildDateDivider(currentDay),
                _buildBubble(item, isMe),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBubble(Map msg, bool isMe) {
    bool isImage = msg['type'] == 'image';
    String senderPhoto = _userPhotos[msg['email']] ?? msg['photo_url'] ?? "";

    return GestureDetector(
      onLongPress: () => _hapusPesan(msg['key'], msg['email']),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) _buildAvatar(senderPhoto, msg['nama']),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: isImage ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? _myChatBubble : _otherChatBubble,
                  borderRadius: _getBorderRadius(isMe),
                  boxShadow: isMe ? [] : [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5, offset: const Offset(0, 2))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isMe && !isImage)
                      Text(msg['nama'], style: TextStyle(color: _accentOrange, fontWeight: FontWeight.bold, fontSize: 10)),
                    if (isImage) _buildImageContent(msg['pesan']) else
                      Text(msg['pesan'], style: TextStyle(color: isMe ? Colors.white : _textBlack, fontSize: 14.5)),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(msg['timestamp'])),
                      style: TextStyle(color: isMe ? Colors.white60 : _textGrey, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String url, String name) {
    return CircleAvatar(
      radius: 15,
      backgroundColor: _borderGrey,
      backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
      child: url.isEmpty ? Text(name[0], style: const TextStyle(fontSize: 10)) : null,
    );
  }

  Widget _buildImageContent(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 200,
        placeholder: (context, url) => Container(height: 150, width: 200, color: _inputBg, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
        errorWidget: (context, url, error) => const Icon(Icons.broken_image),
      ),
    );
  }

  // ✅ PERBAIKAN UTAMA: INPUT AREA YANG RAPI & MODERN
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: _whiteSurface,
        // Shadow halus di atas agar terpisah dari chat list
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 5,
          ),
        ],
        border: Border(top: BorderSide(color: _borderGrey, width: 0.5)),
      ),
      child: SafeArea( // Penting untuk HP modern (Full screen)
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, // Pastikan align tengah
          children: [
            // Tombol Gambar
            IconButton(
              icon: Icon(Icons.add_photo_alternate_outlined, color: _textGrey),
              onPressed: _pilihDanKirimGambar,
              splashRadius: 20,
            ),

            // Kolom Input Teks yang Rapi
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 4, // Bisa memanjang ke atas sampai 4 baris
                style: TextStyle(color: _textBlack, fontSize: 15),
                decoration: InputDecoration(
                  hintText: "Ketik pesan...",
                  hintStyle: TextStyle(color: _textGrey.withValues(alpha: 0.5), fontSize: 14),
                  filled: true,
                  fillColor: _inputBg,
                  isDense: true, // KUNCI: Memadatkan padding internal
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  // Border saat diam
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none, // Polos tanpa garis tajam
                  ),
                  // Border saat diketik
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: _borderGrey, width: 1),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Tombol Kirim yang lebih responsif
            InkWell(
              onTap: _kirimPesan,
              borderRadius: BorderRadius.circular(50),
              child: CircleAvatar(
                backgroundColor: _myChatBubble,
                radius: 22,
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            )
          ],
        ),
      ),
    );
  }

  BorderRadius _getBorderRadius(bool isMe) {
    return BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
    );
  }

  Widget _buildDateDivider(DateTime date) {
    String label = DateFormat('d MMMM yyyy', 'id_ID').format(date);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: _borderGrey, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: _textGrey, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Text("Belum ada pesan.", style: TextStyle(color: _textGrey)));
  }

  Widget _buildUploadingIndicator() {
    return Container(width: double.infinity, color: Colors.blue.withValues(alpha: 0.1), padding: const EdgeInsets.all(8), child: const Text("Sedang mengirim gambar...", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)));
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.black));
  }
}