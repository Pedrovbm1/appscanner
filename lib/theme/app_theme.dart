import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const teal = Color(0xFF00796B);
  static const tealDark = Color(0xFF00695C);
  static const ground = Color(0xFFF3F8F6);
  static const ink = Color(0xFF0E2522);
  static const inkSoft = Color(0xFF33504B);
  static const muted = Color(0xFF4A615D);
  static const tile = Color(0xFFE6F0ED);
  static const chip = Color(0xFFE2EFEB);
  static const border = Color(0xFFDCE8E4);
  static const outline = Color(0xFFB6CCC6);
  static const pageLine = Color(0xFFB8C7C3);
  static const mint = Color(0xFF69F0AE);
  static const mintSoft = Color(0xFFB9F6CA);
  static const onMint = Color(0xFF062A24);
  static const camBg = Color(0xFF070B0A);
  static const camSurface = Color(0xFF1A2321);
  static const camChipOn = Color(0xFF12352F);
  static const camBorder = Color(0xFF34423F);
  static const camText = Color(0xFFF1FAF7);
  static const camTextSoft = Color(0xFFD5E3DF);
  static const camMuted = Color(0xFFA9BDB8);
}

class AppFonts {
  static const display = 'BricolageGrotesque';
  static const body = 'InstrumentSans';
}

class AppTheme {
  static void registerFontLicenses() {
    LicenseRegistry.addLicense(() async* {
      for (final entry in const {
        'Bricolage Grotesque': 'assets/fonts/BricolageGrotesque-OFL.txt',
        'Instrument Sans': 'assets/fonts/InstrumentSans-OFL.txt',
      }.entries) {
        final text = await rootBundle.loadString(entry.value);
        yield LicenseEntryWithLineBreaks([entry.key], text);
      }
    });
  }

  static TextStyle display(double size, {Color? color}) => TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w700,
        fontSize: size,
        letterSpacing: -0.02 * size,
        height: 1.15,
        color: color,
      );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.teal).copyWith(
      primary: AppColors.teal,
      onPrimary: Colors.white,
      surface: AppColors.ground,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.outline,
      outlineVariant: AppColors.border,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: AppFonts.body);
    final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
    const stadium = StadiumBorder();
    const buttonText = TextStyle(fontFamily: AppFonts.body, fontSize: 16, fontWeight: FontWeight.w700);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.ground,
      textTheme: text.copyWith(
        headlineSmall: display(24, color: AppColors.ink),
        titleLarge: display(22, color: AppColors.ink),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.ground,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: display(22, color: AppColors.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: stadium,
          textStyle: buttonText.copyWith(fontSize: 17),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: stadium,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.outline, width: 1.5),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.tealDark,
          textStyle: buttonText,
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.teal, width: 2),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFFC5D5D1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    );
  }

  static ThemeData camera(ThemeData base) {
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.camBg,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.camBg,
        onSurface: AppColors.camText,
        onSurfaceVariant: AppColors.camMuted,
        outline: AppColors.camBorder,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.camBg,
        foregroundColor: AppColors.camText,
        titleTextStyle: display(20, color: AppColors.camText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          foregroundColor: AppColors.camText,
          side: const BorderSide(color: AppColors.camBorder, width: 1.5),
        ),
      ),
      textTheme: base.textTheme.apply(bodyColor: AppColors.camText, displayColor: AppColors.camText),
      iconTheme: const IconThemeData(color: AppColors.camText),
    );
  }
}
