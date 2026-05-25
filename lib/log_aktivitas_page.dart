import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class LogAktivitasPage extends StatelessWidget {
  const LogAktivitasPage({super.key});

  @override
  Widget build(BuildContext context) {
    // --- PALET WARNA (Const Variables) ---
    const Color bgScaffold = Color(0xFFF8F9FA);
    const Color whiteCard = Color(0xFFFFFFFF);
    const Color textBlack = Color(0xFF1A1A1A);
    const Color textGrey = Color(0xFF757575);
    const Color borderGrey = Color(0xFFEEEEEE);
    const Color iconBg = Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bgScaffold,
      appBar: AppBar(
        title: const Text(
          "Log Aktivitas",
          style: TextStyle(fontWeight: FontWeight.w600, color: textBlack),
        ),
        centerTitle: true,
        backgroundColor: whiteCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: textBlack),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: borderGrey, height: 1.0),
        ),
      ),
      body: StreamBuilder(
        stream: FirebaseDatabase.instance.ref("logs").orderByChild("timestamp").onValue,
        builder: (context, snapshot) {
          // 1. Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: textBlack));
          }

          // 2. Data Available
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            Map data = snapshot.data!.snapshot.value as Map;
            List items = data.entries.toList();

            // Urutkan dari yang terbaru (descending)
            items.sort((a, b) => b.value['timestamp'].compareTo(a.value['timestamp']));

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              itemCount: items.length,
              itemBuilder: (context, index) {
                var log = items[index].value;
                DateTime tgl = DateTime.fromMillisecondsSinceEpoch(log['timestamp']);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: whiteCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderGrey),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ikon Kiri
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: iconBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history_edu, size: 20, color: textBlack),
                      ),
                      const SizedBox(width: 16),

                      // Konten Teks
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log['aksi'] ?? "Aksi tidak diketahui",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: textBlack,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.person_outline, size: 14, color: textGrey),
                                const SizedBox(width: 4),
                                Text(
                                  log['admin'] ?? "Sistem",
                                  style: const TextStyle(fontSize: 12, color: textGrey),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.access_time, size: 14, color: textGrey),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('dd MMM HH:mm').format(tgl),
                                  style: const TextStyle(fontSize: 12, color: textGrey),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }

          // 3. Empty State (PERBAIKAN: const ditambahkan di level Center)
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notes_rounded, size: 60, color: Color(0xFFE0E0E0)),
                SizedBox(height: 16),
                Text(
                  "Belum ada catatan aktivitas",
                  style: TextStyle(color: textGrey, fontSize: 16),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}