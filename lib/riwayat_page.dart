import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
/*import 'package:intl/intl.dart';*/

class RiwayatPage extends StatelessWidget {
  final String email;
  final String companyId;

  const RiwayatPage({
    super.key,
    required this.email,
    required this.companyId
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text("Riwayat Aktivitas",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0.5,
          bottom: TabBar(
            labelColor: Colors.blue[800],
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Colors.blue[800],
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: const [Tab(text: "Presensi"), Tab(text: "Izin & Cuti")],
          ),
        ),
        body: TabBarView(
          children: [
            PresensiTab(email: email, companyId: companyId),
            IzinTab(email: email, companyId: companyId),
          ],
        ),
      ),
    );
  }
}

class PresensiTab extends StatelessWidget {
  final String email;
  final String companyId;
  const PresensiTab({super.key, required this.email, required this.companyId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseDatabase.instance
          .ref("companies/$companyId/absensi")
          .orderByChild("email")
          .equalTo(email)
          .onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Text("Belum ada data presensi."));
        }

        final rawData = snapshot.data!.snapshot.value as Map;
        List listItems = rawData.values.toList();
        listItems.sort((a, b) => (b['tanggal'] ?? "").compareTo(a['tanggal'] ?? ""));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: listItems.length,
          itemBuilder: (context, index) {
            final item = listItems[index];
            bool isTelat = item['is_telat'] == true;

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 45,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isTelat ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item['tanggal']?.split('-')[2] ?? "-",
                          style: TextStyle(fontWeight: FontWeight.bold, color: isTelat ? Colors.red : Colors.green)),
                      Text(item['tanggal']?.split('-')[1] ?? "",
                          style: TextStyle(fontSize: 10, color: isTelat ? Colors.red[300] : Colors.green[300])),
                    ],
                  ),
                ),
                title: Text(isTelat ? "Terlambat" : "Hadir Tepat Waktu",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text("Masuk: ${item['jam_masuk'] ?? '--:--'} • Pulang: ${item['jam_keluar'] ?? '--:--'}",
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                trailing: Icon(isTelat ? Icons.report_gmailerrorred : Icons.check_circle,
                    color: isTelat ? Colors.red : Colors.green, size: 24),
              ),
            );
          },
        );
      },
    );
  }
}

class IzinTab extends StatelessWidget {
  final String email;
  final String companyId;
  const IzinTab({super.key, required this.email, required this.companyId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseDatabase.instance
          .ref("companies/$companyId/izin_karyawan")
          .orderByChild("email_karyawan")
          .equalTo(email)
          .onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Text("Belum ada pengajuan izin."));
        }

        final rawData = snapshot.data!.snapshot.value as Map;
        List listItems = rawData.values.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: listItems.length,
          itemBuilder: (context, index) {
            final item = listItems[index];
            String status = (item['status'] ?? "pending").toString().toLowerCase();
            Color statusColor = status == "approved" || status == "disetujui" ? Colors.green : status == "rejected" ? Colors.red : Colors.orange;

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item['jenis_izin'] ?? "Izin",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(status.toUpperCase(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("Tanggal: ${item['tanggal']}",
                        style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    Text(item['alasan'] ?? "-",
                        style: TextStyle(fontSize: 13, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}