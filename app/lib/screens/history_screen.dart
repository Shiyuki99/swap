import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/typography.dart';
import '../services/storage_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/social_icon_row.dart';
import '../widgets/history_card.dart';
import '../models/swap_history.dart';
import '../utils/url_launcher_utils.dart';

class HistoryListScreen extends StatefulWidget {
  const HistoryListScreen({super.key});

  @override
  State<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends State<HistoryListScreen> {
  final StorageService _storageService = StorageService();
  List<SwapHistory> _historyList = [];
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    // Group history by date - newest first (reversed)
    final reversedList = _historyList.reversed.toList();
    final todayHistory = _filterByDate(reversedList, DateTime.now());
    final yesterdayHistory = _filterByDate(
      reversedList,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final olderHistory = reversedList.where((h) {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      return !(h.timestamp.year == today.year &&
              h.timestamp.month == today.month &&
              h.timestamp.day == today.day) &&
          !(h.timestamp.year == yesterday.year &&
              h.timestamp.month == yesterday.month &&
              h.timestamp.day == yesterday.day);
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0.0, 24.0, 0.0, 0),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: EdgeInsetsGeometry.symmetric(vertical: 2),
                margin: EdgeInsetsGeometry.symmetric(horizontal: 10),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('SWAP HISTORY', style: AppTypography.header),
                    // Top Right Button
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        child: Icon(
                          Icons.close,
                          color: AppColors.mainText,
                          size: 26,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Selection count
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    '${_selectedIds.length} selected',
                    style: AppTypography.body.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),

              // History list
              Expanded(
                child: _historyList.isEmpty
                    ? Center(
                        child: Text(
                          'No swap history yet',
                          style: AppTypography.body,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: [
                          if (todayHistory.isNotEmpty) ...[
                            Text(
                              'Today',
                              style: AppTypography.historyTimestamp,
                            ),
                            const SizedBox(height: 12),
                            ...todayHistory.map(
                              (history) => _buildHistoryCard(history),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (yesterdayHistory.isNotEmpty) ...[
                            Text(
                              'Yesterday',
                              style: AppTypography.historyTimestamp,
                            ),
                            const SizedBox(height: 12),
                            ...yesterdayHistory.map(
                              (history) => _buildHistoryCard(history),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (olderHistory.isNotEmpty) ...[
                            Text(
                              'Older',
                              style: AppTypography.historyTimestamp,
                            ),
                            const SizedBox(height: 12),
                            ...olderHistory.map(
                              (history) => _buildHistoryCard(history),
                            ),
                          ],
                        ],
                      ),
              ),

              // Bottom buttons
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        width: double.infinity,
                        text: _isSelectionMode ? 'DELETE' : 'DONE',
                        icon: _isSelectionMode ? Icons.delete : Icons.check,
                        backgroundColor: _isSelectionMode
                            ? AppColors.deleteBg
                            : null,
                        onPressed: _isSelectionMode
                            ? _onDeleteSelected
                            : () => Navigator.pop(context),
                      ),
                    ),
                    if (!_isSelectionMode) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: CustomButton(
                          width: double.infinity,
                          text: 'CLEAR',
                          icon: Icons.delete,
                          backgroundColor: AppColors.deleteBg,
                          onPressed: _onClearPressed,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(SwapHistory history) {
    return HistoryCard(
      history: history,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedIds.contains(history.id),
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (_selectedIds.contains(history.id)) {
              _selectedIds.remove(history.id);
              if (_selectedIds.isEmpty) {
                _isSelectionMode = false;
              }
            } else {
              _selectedIds.add(history.id);
            }
          });
        } else {
          _onHistoryTap(history);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedIds.add(history.id);
          });
        }
      },
    );
  }

  Future<void> _loadHistory() async {
    final history = await _storageService.getSwapHistory();

    if (mounted) {
      setState(() {
        _historyList = history;
      });
    }
  }

  List<SwapHistory> _filterByDate(List<SwapHistory> list, DateTime date) {
    return list.where((history) {
      return history.timestamp.year == date.year &&
          history.timestamp.month == date.month &&
          history.timestamp.day == date.day;
    }).toList();
  }

  void _onHistoryTap(SwapHistory history) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryDetailScreen(history: history),
      ),
    );
  }

  void _onDeleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.mainBg,
        shape: AppTypography.popupShape,
        title: Text(
          'Delete Selected',
          style: AppTypography.popupTitle.copyWith(fontSize: 20),
        ),
        content: Text(
          'Delete ${_selectedIds.length} selected item(s)?',
          style: AppTypography.popupBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTypography.popupAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: AppTypography.popupDestructiveAction),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final id in _selectedIds) {
        await _storageService.deleteSwapHistory(id);
      }
      setState(() {
        _historyList.removeWhere((h) => _selectedIds.contains(h.id));
        _selectedIds.clear();
        _isSelectionMode = false;
      });
    }
  }

  void _onClearPressed() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.mainBg,
        shape: AppTypography.popupShape,
        title: Text(
          'Clear History',
          style: AppTypography.popupTitle.copyWith(fontSize: 20),
        ),
        content: Text(
          'Are you sure you want to clear all swap history?',
          style: AppTypography.popupBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTypography.popupAction),
          ),
          TextButton(
            onPressed: () async {
              await _clearHistory();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: Text('Clear', style: AppTypography.popupDestructiveAction),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    await _storageService.clearSwapHistory();
    setState(() {
      _historyList.clear();
    });
  }
}

// =============================================================================
// Detail Screen
// =============================================================================

class HistoryDetailScreen extends StatefulWidget {
  final SwapHistory history;

  const HistoryDetailScreen({super.key, required this.history});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  String? _selectedPlatform;
  late TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();

    // Select first available platform by default
    final nonEmpty = widget.history.nonEmptyLinks;
    if (nonEmpty.isNotEmpty) {
      _selectedPlatform = nonEmpty.keys.first;
      _updateUsernameDisplay();
    }
  }

  void _updateUsernameDisplay() {
    if (_selectedPlatform != null) {
      final username = widget.history.getUsernameFor(_selectedPlatform!);
      _usernameController.text = username ?? '';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build selectedSocials map from non-empty links
    final nonEmptyLinks = widget.history.nonEmptyLinks;
    final selectedSocials = <String, bool>{};
    for (final key in nonEmptyLinks.keys) {
      selectedSocials[key] = key == _selectedPlatform;
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Header
                        Container(
                          width: double.infinity,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('SWAPPED', style: AppTypography.header),
                              const SizedBox(height: 4),
                              Text(
                                widget.history.username.toUpperCase(),
                                style: AppTypography.subHeader.copyWith(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Swapped links label
                        Text(
                          'SWAPPED LINKS:',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Social icons
                        SocialIconRow(
                          selectedSocials: selectedSocials,
                          socialData: nonEmptyLinks,
                          onSocialTap: (platform) {
                            if (nonEmptyLinks.containsKey(platform)) {
                              setState(() {
                                _selectedPlatform = platform;
                                _updateUsernameDisplay();
                              });
                            }
                          },
                          isEditable: false,
                        ),

                        const SizedBox(height: 24),

                        // Username/Link Row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: CustomTextField(
                                  hintText: '@Username',
                                  controller: _usernameController,
                                  isReadOnly: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              CustomButton(
                                width: 100,
                                text: 'OPEN',
                                icon: Icons.link,
                                backgroundColor: AppColors.openBg,
                                onPressed:
                                    _selectedPlatform != null &&
                                        _usernameController.text.isNotEmpty
                                    ? _onOpenPressed
                                    : null,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Note display (Read only) - only show if there's a note
                        if (widget.history.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.inputBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Note:',
                                    style: AppTypography.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.history.note,
                                    style: AppTypography.input,
                                  ),
                                ],
                              ),
                            ),
                          ),

                        const Spacer(),

                        // Done button
                        CustomButton(
                          width: 150,
                          text: 'DONE',
                          icon: Icons.check,
                          onPressed: () => Navigator.pop(context),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onOpenPressed() {
    if (_selectedPlatform != null && _usernameController.text.isNotEmpty) {
      // Get profile link for platforms that require it
      final linkKey = '${_selectedPlatform}_link';
      final profileLink = widget.history.swappedLinks[linkKey];

      UrlLauncherUtils.openSocialProfile(
        _selectedPlatform!,
        _usernameController.text,
        profileLink: profileLink,
      );
    }
  }
}
