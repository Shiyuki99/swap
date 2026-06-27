import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/typography.dart';

class CustomButton extends StatelessWidget {
  final double width;
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isSecondary;
  final Color? backgroundColor;

  /// If true, the button is "Done" or "Open" style (often smaller width in designs, but width property controls actual size)
  const CustomButton({
    super.key,
    required this.width,
    required this.text,
    this.icon,
    this.onPressed,
    this.isSecondary = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // If onPressed is null, we might want a disabled look,
    // or if the user specified backgroundColor, use it.
    // Default to black (AppColors.buttonBg)
    final bgColor = onPressed == null
        ? AppColors.disabled
        : (backgroundColor ?? AppColors.buttonBg);

    return Container(
      width: width,
      height: 50, // Standard height often used in generic buttons
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: AppTypography.button.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, color: Colors.white, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
