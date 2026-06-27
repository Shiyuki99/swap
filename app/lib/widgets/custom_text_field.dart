import 'package:flutter/material.dart';
import '../../constants/colors.dart';
import '../../constants/typography.dart';

class CustomTextField extends StatelessWidget {
  final String hintText;
  final TextEditingController? controller;
  final int? maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final double? width; // Added width
  final bool isReadOnly;

  const CustomTextField({
    super.key,
    required this.hintText,
    this.controller,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.width,
    this.isReadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width, // Use the width if provided
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: onChanged,
        readOnly: isReadOnly,
        style: AppTypography.input,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), // Rounded
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Colors.black12,
              width: 1,
            ), // Slight border on focus
          ),
          hintText: hintText,
          hintStyle: AppTypography.input.copyWith(
            color: AppColors.secondaryText,
          ),
          counterText: maxLength != null ? '' : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
