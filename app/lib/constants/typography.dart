import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import './colors.dart';

class AppTypography {
  // Headers - Inter
  static TextStyle get header => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: AppColors.mainText,
    letterSpacing: 2,
    wordSpacing: 4,
  );

  // Subheaders
  static TextStyle get subHeader => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.mainText,
    letterSpacing: 1,
  );

  // Body Text - Inter
  static TextStyle get body => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.mainText,
  );

  // Buttons - Inter
  static TextStyle get button => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.lightText,
  );

  // Input Text - Inter
  static TextStyle get input => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.mainText,
  );

  static TextStyle get label => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.secondaryText,
  );

  // History Username - Inter
  static TextStyle get historyUsername => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.mainText,
  );

  // History Note - Inter
  static TextStyle get historyNote => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.mainText,
  );

  // History Time - Inter
  static TextStyle get historyTime => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.secondaryText,
  );

  // History Timestamps (Today, Yesterday) - Inter
  static TextStyle get historyTimestamp => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.secondaryText,
  );

  // ── Popup / Dialog styles ──────────────────────────────────────────────
  static Color get popupTextColor =>
      AppColors.isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1A1A2E);

  static TextStyle get popupTitle => GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: popupTextColor,
  );

  static TextStyle get popupBody => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: popupTextColor.withValues(alpha: 0.7),
    height: 1.5,
  );

  static TextStyle get popupAction => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: popupTextColor,
  );

  static TextStyle get popupDestructiveAction => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.deleteBg,
  );

  static ShapeBorder popupShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
  );
}
