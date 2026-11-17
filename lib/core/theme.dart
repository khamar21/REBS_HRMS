import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF5B5FEF);
  static const primaryDark = Color(0xFF292C78);
  static const bg = Color(0xFFF4F6FC);
  static const ink = Color(0xFF171A36);
  static const muted = Color(0xFF69708D);
  static const success = Color(0xFF16A673);
  static const warning = Color(0xFFE99B22);
  static const danger = Color(0xFFD94A68);
  static const glassWhite = Color(0xCCFFFFFF);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  );
  final textTheme = GoogleFonts.poppinsTextTheme().apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: GoogleFonts.poppins().fontFamily,
    splashFactory: InkSparkle.splashFactory,
    iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
    primaryIconTheme: const IconThemeData(color: Colors.white, size: 22),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.ink,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 78,
      backgroundColor: Colors.white.withValues(alpha: .94),
      indicatorColor: AppColors.primary.withValues(alpha: .16),
      elevation: 8,
      shadowColor: AppColors.primaryDark.withValues(alpha: .12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: BorderSide(color: AppColors.primary.withValues(alpha: .2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        textStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .78),
      labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: AppColors.muted.withValues(alpha: .72),
      ),
    ),
  );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: .78)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: .07),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}
