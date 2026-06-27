import 'package:flutter/material.dart';
import '../../constants/colors.dart';
import '../../constants/typography.dart';
import '../../models/swap_history.dart';

class HistoryCard extends StatelessWidget {
  final SwapHistory history;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const HistoryCard({
    super.key,
    required this.history,
    required this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // Get non-empty social links
    final socials = history.nonEmptyLinks;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.inputBg.withValues(alpha: 0.8)
              : AppColors.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Color.fromARGB(255, 18, 172, 243), width: 2)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSelectionMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
                activeColor: const Color.fromARGB(255, 18, 172, 243),
              ),
              const SizedBox(width: 8),
            ],

            // Main content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username
                  Text(history.username, style: AppTypography.historyUsername),
                  const SizedBox(height: 4),

                  // Swapped socials (show only non-empty)
                  if (socials.isNotEmpty) ...[
                    Text(
                      'Swapped: ${socials.keys.map((k) => k[0].toUpperCase() + k.substring(1)).join(', ')}',
                      style: AppTypography.historyNote.copyWith(
                        color: AppColors.secondaryText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Note (if any)
                  if (history.note.isNotEmpty) ...[
                    Text(
                      history.note,
                      style: AppTypography.historyNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Timestamp
                  Text(
                    _formatTimestamp(history.timestamp),
                    style: AppTypography.historyTime,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')} - ${timestamp.day} ${_getMonthName(timestamp.month)} ${timestamp.year}';
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
