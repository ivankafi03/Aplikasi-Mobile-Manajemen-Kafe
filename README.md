<h1 align="center">
  ☕ Aplikasi Mobile Manajemen Kafe
</h1>

<p align="center">
  <b>Realtime Shift Monitoring & Scheduling System</b><br/>
  Studi Kasus: Kafe Sri Rahajoe, Jombang
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
  <img src="https://img.shields.io/badge/Firebase-Realtime-FFCA28?style=for-the-badge&logo=firebase&logoColor=black"/>
  <img src="https://img.shields.io/badge/Supabase-Storage-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white"/>
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Status-Completed-brightgreen?style=for-the-badge"/>
</p>

---

## 📌 Tentang Proyek

Aplikasi mobile berbasis **Flutter** yang dirancang untuk **mengotomasi dan memonitoring** manajemen shift kerja karyawan kafe secara realtime. Proyek ini merupakan bagian dari **Tugas Akhir** yang dikembangkan sebagai solusi atas permasalahan pencatatan manual dan komunikasi shift yang tidak efisien di lingkungan kafe.

> 💡 Sebelum aplikasi ini ada, manajemen shift dilakukan secara manual via kertas dan grup WhatsApp — rentan terhadap miskomunikasi dan ketidakhadiran yang tidak terdeteksi.

---

## ✨ Fitur Utama

### 👤 Untuk Karyawan
| Fitur | Deskripsi |
|---|---|
| 📍 **Absensi QR + GPS** | Check-in/out menggunakan QR Code dengan validasi lokasi GPS |
| 📅 **Lihat Jadwal Shift** | Tampilan kalender jadwal shift mingguan & bulanan |
| 🔄 **Tukar Shift** | Ajukan tukar shift dengan rekan, menunggu persetujuan admin |
| 📝 **Pengajuan Izin** | Ajukan izin/sakit langsung dari aplikasi |
| 💬 **Chat Internal** | Komunikasi tim tanpa keluar dari aplikasi |
| 🔔 **Push Notification** | Notifikasi realtime untuk jadwal & pengumuman |
| 👤 **Profil & Riwayat** | Kelola profil dan lihat riwayat absensi |

### 🛠️ Untuk Admin / Manager
| Fitur | Deskripsi |
|---|---|
| 📊 **Dashboard Realtime** | Overview kehadiran, jadwal, dan status karyawan |
| 🗓️ **Kelola Jadwal Shift** | Buat, edit, dan publish jadwal shift karyawan |
| ✅ **Approval Center** | Setujui/tolak pengajuan izin dan tukar shift |
| 👥 **Manajemen Karyawan** | Tambah, edit, nonaktifkan akun karyawan |
| 📈 **Laporan Kehadiran** | Ekspor dan analisis data kehadiran |
| 💰 **Aturan Gaji** | Konfigurasi aturan perhitungan gaji/shift |
| 📡 **Monitoring Realtime** | Pantau status kehadiran secara langsung |
| 📢 **Kelola Info & Pengumuman** | Kirim info ke seluruh karyawan |
| 📋 **Log Aktivitas** | Rekam jejak seluruh aktivitas sistem |

---

## 🏗️ Arsitektur & Tech Stack

```
┌─────────────────────────────────────────────┐
│              Flutter App (UI Layer)          │
│         Material 3 · White Elegant Theme    │
└────────────────────┬────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
  ┌──────────┐ ┌──────────┐ ┌──────────────┐
  │ Firebase │ │ Firebase │ │   Supabase   │
  │   Auth   │ │Realtime  │ │   Storage    │
  │          │ │    DB    │ │ (Foto Profil)│
  └──────────┘ └──────────┘ └──────────────┘
        │
  ┌──────────┐
  │ Firebase │
  │Messaging │
  │   (FCM)  │
  └──────────┘
```

### 📦 Dependencies Utama

| Kategori | Package |
|---|---|
| **Backend & Auth** | `firebase_core`, `firebase_auth`, `firebase_database`, `firebase_messaging` |
| **Storage** | `supabase_flutter`, `image_picker`, `image_cropper` |
| **Absensi** | `mobile_scanner` (QR), `geolocator` (GPS) |
| **Maps** | `flutter_map`, `latlong2` |
| **QR Generator** | `qr_flutter` |
| **Chart & Analitik** | `fl_chart` |
| **Kalender** | `table_calendar` |
| **Notifikasi** | `flutter_local_notifications` |
| **Animasi** | `lottie`, `cached_network_image` |
| **Utilities** | `intl`, `shared_preferences`, `uuid`, `logger` |

---

## 📱 Struktur Halaman

```
lib/
├── main.dart                    # Entry point, konfigurasi Firebase & Notifikasi
├── login_page.dart              # Halaman login
├── register_cafe_page.dart      # Registrasi kafe baru
├── admin_setup_page.dart        # Setup awal admin
├── dashboard_page.dart          # Dashboard utama (Admin & Karyawan)
├── absensi_page.dart            # Absensi via QR & GPS
├── kelola_jadwal_page.dart      # Manajemen jadwal shift
├── monitoring_page.dart         # Monitoring kehadiran realtime
├── approval_page.dart           # Approval izin
├── approval_tukar_page.dart     # Approval tukar shift
├── form_tukar_shift.dart        # Form pengajuan tukar shift
├── pilih_pengganti_page.dart    # Pilih pengganti shift
├── izin_page.dart               # Pengajuan izin
├── karyawan_management_page.dart# Manajemen data karyawan
├── laporan_page.dart            # Laporan kehadiran
├── aturan_gaji_page.dart        # Konfigurasi aturan gaji
├── chat_page.dart               # Chat internal
├── kelola_info_page.dart        # Kelola pengumuman
├── profil_page.dart             # Profil pengguna
├── riwayat_page.dart            # Riwayat absensi
├── log_aktivitas_page.dart      # Log aktivitas sistem
├── pengaturan_cafe_page.dart    # Pengaturan kafe
├── notification_helper.dart     # Helper notifikasi
└── firebase_options.dart        # Konfigurasi Firebase
```

---

## 🚀 Cara Menjalankan

### Prasyarat
- Flutter SDK `>=3.2.3`
- Android Studio / VS Code
- Akun Firebase (konfigurasi sendiri)
- Akun Supabase (untuk storage foto profil)

### Langkah Instalasi

```bash
# 1. Clone repository
git clone https://github.com/ivankafi03/Aplikasi-Mobile-Manajemen-Kafe.git
cd Aplikasi-Mobile-Manajemen-Kafe

# 2. Install dependencies
flutter pub get

# 3. Konfigurasi Firebase
# - Buat project di Firebase Console
# - Download google-services.json (Android) / GoogleService-Info.plist (iOS)
# - Jalankan: flutterfire configure

# 4. Konfigurasi Supabase
# - Buat project di Supabase
# - Update supabaseUrl & supabaseAnonKey di main.dart

# 5. Jalankan aplikasi
flutter run
```

> ⚠️ **Catatan:** File `firebase_options.dart` dan konfigurasi Supabase menggunakan environment project sendiri. Pastikan membuat project Firebase & Supabase baru saat ingin menjalankan secara mandiri.

---

## 🔐 Role & Akses

| Role | Akses |
|---|---|
| **Admin** | Akses penuh: kelola karyawan, jadwal, approval, laporan, pengaturan kafe |
| **Karyawan** | Absensi, lihat jadwal, ajukan izin/tukar shift, chat, profil |

---

## 📊 Alur Sistem

```
Karyawan          App                    Firebase              Admin
   │               │                        │                    │
   │─── Login ────►│──── Auth ─────────────►│                    │
   │               │◄─── Session ───────────│                    │
   │               │                        │                    │
   │── Absensi ───►│── Validasi GPS/QR ─────►│                   │
   │               │◄─── Berhasil ──────────│                    │
   │               │                        │─── Push Notif ────►│
   │               │                        │                    │
   │── Tukar Shift►│── Simpan Request ──────►│                   │
   │               │                        │─── Notif ─────────►│
   │               │                        │       │            │
   │               │                        │◄── Approve/Reject ─│
   │◄── Notif ─────│◄────────────────────────│                   │
```

---

## 👨‍💻 Developer

**Tugas Akhir — Teknik Informatika**
- 📍 Studi Kasus: Kafe Sri Rahajoe, Jombang
- 🎓 Dibuat sebagai persyaratan kelulusan

---

## 📄 Lisensi

Proyek ini dilisensikan di bawah [MIT License](LICENSE).

---

<p align="center">
  Dibuat dengan ❤️ menggunakan Flutter & Firebase
</p>
