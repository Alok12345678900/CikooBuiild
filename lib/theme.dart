import 'package:flutter/material.dart';

const Color kRed = Color(0xFFFF1A1A);
const Color kBg = Color(0xFF07070B);
const Color kCard = Color(0xFF111118);
const Color kMuted = Color(0xFF888888);
const Color kGreen = Color(0xFF00E676);
const Color kBorder = Color(0xFF22222A);
const Color kInputBg = Color(0xFF0A0A0F);
const Color kSecondaryBtn = Color(0xFF1C1C24);

ThemeData buildTheme() {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: kBorder, width: 1),
  );

  const focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: kRed, width: 1.5),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      primary: kRed,
      onPrimary: Colors.white,
      secondary: kSecondaryBtn,
      surface: kCard,
      surfaceTint: Colors.transparent,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: kInputBg,
      border: border,
      enabledBorder: border,
      focusedBorder: focusedBorder,
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Colors.redAccent, width: 1),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: kMuted),
      hintStyle: TextStyle(color: kMuted, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
    // Teks SnackBar bawaan gelap di atas latar gelap (tampak kosong) -> paksa putih.
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kCard,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
      actionTextColor: kRed,
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: kCard,
      indicatorColor: Color(0x33FF1A1A),
      labelTextStyle: MaterialStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
    cardTheme: CardThemeData(
      color: kCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kBorder, width: 1),
      ),
    ),
  );
}

String timeAgo(int millis) {
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
  if (diff.inSeconds < 60) return 'baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  return '${diff.inDays} hari lalu';
}