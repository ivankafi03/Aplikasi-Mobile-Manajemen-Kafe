import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

class NotificationHelper {
  // =========================================================================
  // KUNCI RAHASIA (SERVICE ACCOUNT)
  // =========================================================================
  static const Map<String, dynamic> serviceAccountJson = {
    "type": "service_account",
    "project_id": "kafe-sri-rahajoe",
    "private_key_id": "cd745a3258d11d7bff9f64d4d63b97ecb3a29bc8",
    // Gunakan Raw String (r) dan Triple Quotes (""")
    "private_key": r"""-----BEGIN PRIVATE KEY-----
MIIEugIBADANBgkqhkiG9w0BAQEFAASCBKQwggSgAgEAAoIBAQC0bH86jPNLTO4q
EQNpJHOZwPgwmDaqIJbjJTlan7WZ2MJh5CZdWf8qNHBvKKASMZimviUPscZwIIMN
O7XlazdScUHYVya8r8a9OfR87hyjFQliwvhkVJwolmjglnnsPnftQ1Rkc39uSmz8
XHkxUN0JaksjC+qrgecl2D7MVokVA4JA3c4kVjIMjmIrRdyV6Oq83CyIj08Qj+zL
oAuLNqEhZSQuo2DUgs0ei+ZS/kF6Hgb0csIMUjnQmJ5PH4gtz18V9atX2tI0I0C3
+jdfQo8U0vtvpHA//bcVyLosx453nW4YzApvsGvxzWKHmHll7uHFWbYMresnR/wX
LC5xsOQzAgMBAAECggEAJUdJnmpjForlprFvN/k9HWaeoUPB/7LOGk6lpBDdr9T2
jM1cE+u1ah39oSoOsNOoi8M72xtLOf2ttj1BHw7hFlqqVS3kphXXhV+FIY79QcDl
+I76TZihz00MjGLq/CIIG3DO7hZjHQGptRbSP5tKoFhi//HFYfxsKwicKRI0Lq/6
3nb8yfoRP+3/fOMGWbA4Ges5wVQ78tPUpKq++kI32eBV2RkGtnt/9rAHfHQDPLkJ
nl4EGnwFmibtJ3DS4Xj71Apy9kDbUs+ZGDTMcXpkib4R6icIqPR04BvftI8ARTB/A
nARadzcI6jXT+0xW0Y5QK/Xk1w+KeiWC/62M3R+fSQKBgQDm6BmcUVvVXHNYFsEE
3t29lrWSex+x7K6gsWP2SqDjr+iAMxQvJjU3JuiBUZJ7HaVBWhZU9z5qNgcA7Lxe
lw+Y+S7IB30h1R6Q5CUlp2pkg9KGJQhELcgaDxhXPmw8tKiwKu4xCQCKVugS99Ox
ZX0k+OBec1n7W9fFnywSDpt07QKBgQDIB/Ko338Em2Y83NUXmi7a6ERKJaxQdUXK
TnafDgJGUVM0boa/Mrt+hVq35bIvWUWDVCwGib478u/FqaZ5aKHhHh+4xv2mfRj0
WeNyEPl6KlPPya4Jtuforr3FABE6Rvj2f7k9LIFVVxYfDC4VO528YKxfPNWxtvuU
6tKE9bS5nwJ/KmRyT0Cgm4tdoc6LoVlJXIVO0JXKO+A4L0hiEdWhtCuXg/HcwstA
+d8q0JMpUXEf5d+kOfUqgFVq88CC1NrnAi69Z/v3/T4jXnaEW2VhIxMQk5A49Etz
cVVUIrBTLtH8Jlu7X0VH1B4gfVsCgo8faqpGhxCmdH9oHeAbNzV3VQKBgGmFJ9FF
9S9s+sXoiNDmmQkJtdyXewsGkkZildjZ/wExLX9fPt3l2Vqo5m5UUWcA5NaetIrO
Zvgg87OGBzfMpnim93z2HCCTpXJhaMZnhfOYGJZogdLGFhh89cbSfkQL5JHEVuea
bq+iPR0rw7OXu2IAbW3gHaqeKKEqLtvM8gVpAoGACTUDCu286xv1xKTJOKO+1HUK
D2SiCGDl5uOKvzVbh5nH+OsR/ni2HBQAIdC2owrAaFH47/8y8QTVWY8L1olUoAdk
h33RpkEQzYe0nT/cOpIzcdhTITXFV2g1cFxQJsdjQHDaex5wVT+cZ+/Uqmy+gcOl
DZDdB/5/atJE8Bfyp6Y=
-----END PRIVATE KEY-----""",
    "client_email": "firebase-adminsdk-fbsvc@kafe-sri-rahajoe.iam.gserviceaccount.com",
    "client_id": "112243406647882641872",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40kafe-sri-rahajoe.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com"
  };

  static const _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  // Fungsi untuk mendapatkan Access Token dari Google OAuth2
  static Future<String?> _getAccessToken() async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
      final client = await clientViaServiceAccount(accountCredentials, _scopes);
      return client.credentials.accessToken.data;
    } catch (e) {
      debugPrint("❌ Error ambil Access Token: $e");
      return null;
    }
  }

  // Fungsi Kirim Notifikasi Utama
  static Future<void> sendNotification({
    required String targetToken,
    required String title,
    required String body,
    String? senderId, // Parameter baru untuk identitas pengirim
    Map<String, dynamic>? data,
  }) async {
    final String? accessToken = await _getAccessToken();
    if (accessToken == null) return;

    final String projectId = serviceAccountJson['project_id'];
    final String endpoint = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

    // Menyiapkan data payload (wajib berupa Map<String, String> untuk FCM v1)
    Map<String, String> stringData = {};

    // Masukkan sender_id agar bisa difilter di main.dart
    if (senderId != null) {
      stringData['sender_id'] = senderId;
    }

    if (data != null) {
      data.forEach((key, value) => stringData[key] = value.toString());
    } else {
      stringData["click_action"] = "FLUTTER_NOTIFICATION_CLICK";
      stringData["type"] = "general";
    }

    // DI DALAM notification_helper.dart, bagian fungsi sendNotification
    // Di notification_helper.dart, ubah bagian 'message' menjadi:
    final Map<String, dynamic> message = {
      "message": {
        "token": targetToken,
        // JANGAN ADA BLOK "notification" DI SINI
        "data": {
          ...stringData,
          "title": title, // Kirim sebagai data agar ditangkap onMessage
          "body": body,
        },
        "android": {
          "priority": "high",
        }
      }
    };

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        debugPrint("✅ Notifikasi terkirim");
      } else {
        debugPrint("⚠️ Gagal kirim: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Error HTTP: $e");
    }
  }
}