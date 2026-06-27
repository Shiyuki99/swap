import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/typography.dart';

class ProfileTabSwitcher extends StatelessWidget {
  final int activeProfile;
  final Function(int) onProfileChanged;
  const ProfileTabSwitcher({
    super.key,
    required this.activeProfile,
    required this.onProfileChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_buildTab('Profile 1', 0), _buildTab('Profile 2', 1)],
      ),
    );
  }

  Widget _buildTab(String text, int index) {
    final isActive = activeProfile == index;
    return GestureDetector(
      onTap: () => onProfileChanged(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.buttonBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: AppTypography.body.copyWith(
            color: isActive ? AppColors.lightText : AppColors.mainText,
          ),
        ),
      ),
    );
  }
}
