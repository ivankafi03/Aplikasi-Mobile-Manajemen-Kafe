import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';

// --- PLUGIN TAMBAHAN ---
import 'package:lottie/lottie.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- OPTION & HALAMAN ---
import 'firebase_options.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'monitoring_page.dart';
import 'approval_page.dart';

// ==================================================
// 🎨 PALET WARNA (WHITE ELEGANT THEME - RESTORED)
// ==================================================
const Color bgScaffold = Color(0xFFF8F9FA);
const Color elegantBlack = Color(0xFF212121);
const Color textBlack = Color(0xFF1A1A1A);
const Color textGrey = Color(0xFF757575);
const Color whiteSurface = Color(0xFFFFFFFF);
// Tambahan warna error agar konsisten
const Color errorRed = Color(0xFFD32F2F);

// --- Konfigurasi Supabase ---
const String supabaseUrl = 'https://idqqgrbgamjxfhulqift.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlkcXFncmJnYW1qeGZodWxxaWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxNTY5MjEsImV4cCI6MjA4MjczMjkyMX0.QoVo7zgM48T_brE6RE78HWH1v_D_9MyxXBOLOBoyjDo';

// ==================================================
// 🏢 GLOBAL DATA CLASS
// ==================================================
class GlobalData {
  static String? currentCompanyId;
  static String? currentUserId;
  static String? currentUserName;
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// --- SETUP NOTIFIKASI CHANNEL ---
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'Notifikasi Penting',
  description: 'Channel ini digunakan untuk notifikasi penting Kafe Sri Rahajoe.',
  importance: Importance.high,
  playSound: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("📱 Background Message: ${message.notification?.title}");

  // LOGIC FIX: Tidak menampilkan notifikasi manual di sini agar tidak double.
  // Sistem Android akan otomatis menanganinya.
}

void _handleNotificationNavigation(RemoteMessage message) {
  final data = message.data;
  debugPrint("📱 Navigasi Notifikasi: ${data['category']}");

  if (data['category'] == 'late_attendance' || data['category'] == 'attendance') {
    if (GlobalData.currentCompanyId != null) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (context) => MonitoringPage(companyId: GlobalData.currentCompanyId!),
      ));
    }
  } else if (data['category'] == 'leave_request') {
    if (GlobalData.currentCompanyId != null) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (context) => ApprovalPage(companyId: GlobalData.currentCompanyId!),
      ));
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await initializeDateFormatting('id_ID', null);
  FirebaseDatabase.instance.setPersistenceEnabled(true);

  // Setup Notification Local
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload == 'attendance' || response.payload == 'late_attendance') {
        if (GlobalData.currentCompanyId != null) {
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (context) => MonitoringPage(companyId: GlobalData.currentCompanyId!),
          ));
        }
      } else if (response.payload == 'leave_request') {
        if (GlobalData.currentCompanyId != null) {
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (context) => ApprovalPage(companyId: GlobalData.currentCompanyId!),
          ));
        }
      }
    },
  );

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false, // Biar sistem nggak nampilin notif dobel pas aplikasi dibuka
    badge: true,
    sound: true,
  );

  // DI DALAM main.dart
  // DI DALAM main.dart, bagian onMessage listener
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Ambil data langsung dari Map 'data'
    final String? title = message.data['title'];
    final String? body = message.data['body'];
    final String? senderId = message.data['sender_id'];

    // Filter 1: Cek apakah pengirim adalah kita sendiri
    if (senderId != null && senderId == GlobalData.currentUserId) {
      debugPrint("🚫 Mengabaikan notifikasi dari diri sendiri.");
      return;
    }

    // Filter 2: Tampilkan secara manual menggunakan Local Notifications
    if (title != null && body != null) {
      flutterLocalNotificationsPlugin.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            color: elegantBlack,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: 'Kafe Sri Rahajoe',
            ),
          ),
        ),
        payload: message.data['category'],
      );
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationNavigation);
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationNavigation(initialMessage);
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Kafe Sri Rahajoe',
      debugShowCheckedModeBanner: false,

      // ==================================================
      // 🎨 TEMA LIGHT MODE (ELEGAN) - RESTORED
      // ==================================================
      theme: ThemeData(
        useMaterial3: true,

        // Skema Warna Utama (Light)
        colorScheme: ColorScheme.fromSeed(
          seedColor: elegantBlack,
          primary: elegantBlack,    // Warna utama Hitam Elegan
          secondary: Colors.blueGrey,
          surface: bgScaffold,      // Background Putih Abu
          onSurface: textBlack,     // Teks Hitam
          error: errorRed,
        ),

        scaffoldBackgroundColor: bgScaffold,

        appBarTheme: const AppBarTheme(
          backgroundColor: whiteSurface,
          foregroundColor: textBlack,
          centerTitle: true,
          elevation: 0,
        ),

        // Pengaturan Card (Wajib CardThemeData agar tidak error)
        cardTheme: CardThemeData(
          color: whiteSurface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: elegantBlack,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: whiteSurface,
          hintStyle: const TextStyle(color: textGrey),
          prefixIconColor: elegantBlack,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: elegantBlack, width: 2),
          ),
        ),
      ),

      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _handleStartup();
  }

  void _handleStartup() {
    Timer(const Duration(seconds: 4), () async {
      firebase_auth.User? user = firebase_auth.FirebaseAuth.instance.currentUser;

      if (user != null) {
        try {
          final snapshot = await FirebaseDatabase.instance
              .ref("users/${user.uid}")
              .get()
              .timeout(const Duration(seconds: 10), onTimeout: () {
            throw TimeoutException("Koneksi Firebase Lemot");
          });

          if (snapshot.exists && mounted) {
            Map data = snapshot.value as Map;
            String companyId = data['company_id']?.toString() ?? "";

            GlobalData.currentCompanyId = companyId;
            GlobalData.currentUserId = user.uid;
            GlobalData.currentUserName = data['nama']?.toString() ?? "User";

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DashboardPage(
                  nama: data['nama']?.toString() ?? "User",
                  role: data['role']?.toString() ?? "karyawan",
                  companyId: companyId,
                  email: user.email ?? "user@kafe.com",
                  uid: user.uid,
                  photoUrl: data['photo_url']?.toString() ?? "",
                ),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint("❌ Error Session: $e");
        }
      }

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgScaffold, // Background Putih Abu
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // Lottie Animation
            Lottie.asset(
              'assets/animations/coffee_anim.json',
              width: 180,
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback jika animasi gagal load
                return const Icon(Icons.coffee_rounded, size: 100, color: elegantBlack);
              },
            ),

            const SizedBox(height: 20),

            const Text(
              "Kafe Sri Rahajoe",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: textBlack, // Teks Hitam
                letterSpacing: 1.2,
                fontFamily: 'Serif',
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              "Realtime Monitoring & Scheduling",
              style: TextStyle(
                  color: textGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5
              ),
            ),

            const SizedBox(height: 50),

            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: elegantBlack), // Loading Hitam
            )
          ],
        ),
      ),
    );
  }
}