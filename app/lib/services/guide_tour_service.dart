import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/typography.dart';
import '../models/profile.dart';
import '../screens/edit_screen.dart';
import '../screens/result_screen.dart';

const _kGuideKey = 'guide_tour_completed';

// ============================================================================
// GUIDE TOUR SERVICE
// ============================================================================

class GuideTourService {
  // Static GlobalKeys — edit/result screens attach these to their widgets
  static final editProfileTabKey = GlobalKey();
  static final editNameFieldsKey = GlobalKey();
  static final editSocialIconsKey = GlobalKey();
  static final editSaveButtonKey = GlobalKey();
  static final resultOpenButtonKey = GlobalKey();

  /// Check if user has never completed the tour
  static Future<bool> shouldShowTour() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kGuideKey) ?? false);
  }

  /// Mark the tour as completed so it never shows again
  static Future<void> _markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGuideKey, true);
  }

  /// Run the full app tour. Call from HomeScreen after first build.
  static Future<void> startTour(
    BuildContext context, {
    GlobalKey? swapButtonKey,
    GlobalKey? editButtonKey,
    GlobalKey? historyIconKey,
    GlobalKey? settingsIconKey,
  }) async {
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!;
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;
    final topPad = mq.padding.top;

    Rect? rectOf(GlobalKey? key) {
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    // ── Step 1: Welcome ──────────────────────────────────────────────────
    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Welcome to SWAP!',
      desc: "Let's take a quick tour to show\nyou how everything works.",
      buttonText: "LET'S GO",
    )) {
      return;
    }

    // ── Step 2: Swap Button ──────────────────────────────────────────────
    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Swap Button',
      desc: 'Tap here to start sharing\nyour profile with others.',
      spotlight: rectOf(swapButtonKey),
    )) {
      return;
    }

    // ── Step 3: Navigate to Edit ─────────────────────────────────────────
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const EditScreen(initialProfileIndex: 0),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 450));

    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Select Profile',
      desc: 'Switch between Profile 1 and\nProfile 2 to edit each one.',
      spotlight: rectOf(editProfileTabKey),
    )) {
      navigator.pop();
      return;
    }

    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Your Info',
      desc: 'Enter your profile name and\ndisplay name here.',
      spotlight: rectOf(editNameFieldsKey),
    )) {
      navigator.pop();
      return;
    }

    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Add Socials',
      desc:
          'Tap an icon to select a platform,\nthen enter your username or link.',
      spotlight: rectOf(editSocialIconsKey),
    )) {
      navigator.pop();
      return;
    }

    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Save',
      desc: 'Press Save when you\'re done.',
      spotlight: rectOf(editSaveButtonKey),
    )) {
      navigator.pop();
      return;
    }

    // Pop edit
    navigator.pop();
    await Future.delayed(const Duration(milliseconds: 400));

    // ── Step 4: Share explanation
    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Sharing',
      desc:
          'After saving, tap Swap to share.\nOthers scan your QR or tap via NFC.',
    )) {
      return;
    }

    // ── Step 5: Result screen with demo profile ──────────────────────────
    final demoProfile = Profile(
      id: 'demo',
      profileName: 'Demo',
      name: 'Shiyuki',
      socialLinks: {
        'instagram': 'shiyuki',
        'twitter': 'shiyuki',
        'github': 'Shiyuki99',
        'discord': '',
        'snapchat': '',
        'tiktok': '',
        'email': '',
        'phone': '',
      },
    );
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(receivedProfile: demoProfile),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 450));

    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Swapped!',
      desc: 'See their profile and tap\nOpen to visit their socials.',
      spotlight: rectOf(resultOpenButtonKey),
    )) {
      navigator.pop();
      return;
    }

    // Pop result
    navigator.pop();
    await Future.delayed(const Duration(milliseconds: 400));

    // ── Step 6: Edit button ──────────────────────────────────────────────
    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Edit Anytime',
      desc: 'Edit your profile whenever you want.',
      spotlight: rectOf(editButtonKey),
    )) {
      return;
    }

    // ── Step 7: Swipe to switch ──────────────────────────────────────────
    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Switch Profiles',
      desc: 'Swipe over the swap button\nto change profile.',
      spotlight: rectOf(swapButtonKey),
    )) {
      return;
    }

    // ── Step 8: History ──────────────────────────────────────────────────
    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Swap History',
      desc: 'View your previous swaps here.',
      spotlight: rectOf(historyIconKey)?.inflate(8),
    )) {
      return;
    }

    // ── Step 9: Settings ─────────────────────────────────────────────────
    if (await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: 'Settings',
      desc: 'Tap here to access your settings.',
      spotlight: rectOf(settingsIconKey)?.inflate(8),
    )) {
      return;
    }

    // ── Done ─────────────────────────────────────────────────────────────
    await _step(
      overlay: overlay,
      screenSize: screenSize,
      topPad: topPad,
      title: "You're All Set!",
      desc: 'Enjoy swapping your socials!\nHave fun meeting new people. 🎉',
      buttonText: 'START',
    );

    await _markCompleted();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Show a single step overlay. Returns true if skipped.
  // ────────────────────────────────────────────────────────────────────────
  static Future<bool> _step({
    required OverlayState overlay,
    required Size screenSize,
    required double topPad,
    required String title,
    required String desc,
    Rect? spotlight,
    String buttonText = 'NEXT',
  }) {
    final completer = Completer<bool>();
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _GuideStepWidget(
        screenSize: screenSize,
        topPad: topPad,
        title: title,
        description: desc,
        spotlightRect: spotlight,
        buttonText: buttonText,
        onNext: () {
          entry.remove();
          completer.complete(false);
        },
        onSkip: () {
          entry.remove();
          _markCompleted();
          completer.complete(true);
        },
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}

// ============================================================================
// GUIDE STEP WIDGET (overlay UI for a single step)
// ============================================================================

class _GuideStepWidget extends StatelessWidget {
  final Size screenSize;
  final double topPad;
  final String title;
  final String description;
  final Rect? spotlightRect;
  final String buttonText;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _GuideStepWidget({
    required this.screenSize,
    required this.topPad,
    required this.title,
    required this.description,
    required this.spotlightRect,
    required this.buttonText,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Card positioning strategy:
    // - If no spotlight OR spotlight is NOT in the center band → center the card
    // - If spotlight IS in the center band → put card above or below to avoid overlap
    bool centerCard = true;
    double? cardTop;
    double? cardBottom;

    if (spotlightRect != null) {
      final spotCenter = spotlightRect!.center.dy;
      final inCenterBand =
          spotCenter > screenSize.height * 0.3 &&
          spotCenter < screenSize.height * 0.7;

      if (inCenterBand) {
        // Spotlight is in the middle — offset the card
        centerCard = false;
        final spotInUpperHalf = spotCenter < screenSize.height * 0.5;
        if (spotInUpperHalf) {
          cardTop = spotlightRect!.bottom + 24;
          final maxTop = screenSize.height - bottomPad - 240;
          if (cardTop > maxTop) cardTop = maxTop;
        } else {
          cardBottom = screenSize.height - spotlightRect!.top + 24;
          final maxBottom = screenSize.height - topPad - 80;
          if (cardBottom > maxBottom) cardBottom = maxBottom;
        }
      }
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dark overlay with spotlight cutout
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                spotlightRect: spotlightRect,
                overlayColor: Colors.black.withValues(alpha: 0.78),
              ),
            ),
          ),

          // "APP GUIDE" header
          Positioned(
            top: topPad + 16,
            left: 0,
            right: 0,
            child: Text(
              'APP GUIDE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
          ),

          // Skip button (bottom right, above safe area)
          Positioned(
            bottom: bottomPad + 24,
            right: 24,
            child: GestureDetector(
              onTap: onSkip,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'SKIP',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),

          // Explanation card
          if (!centerCard)
            Positioned(
              left: 28,
              right: 28,
              top: cardTop,
              bottom: cardBottom,
              child: _buildCard(),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _buildCard(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTypography.popupTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: AppTypography.popupBody,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onNext,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1CB1D3), Color(0xFF792EA4)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1CB1D3).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SPOTLIGHT PAINTER — dark overlay with a transparent hole
// ============================================================================

class _SpotlightPainter extends CustomPainter {
  final Rect? spotlightRect;
  final Color overlayColor;

  _SpotlightPainter({this.spotlightRect, required this.overlayColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    // Full dark overlay
    canvas.drawRect(Offset.zero & size, Paint()..color = overlayColor);

    // Cut out the spotlight hole
    if (spotlightRect != null) {
      final padded = spotlightRect!.inflate(10);
      final isCircular = (padded.width - padded.height).abs() < 40;
      final radius = isCircular ? padded.width / 2 : 16.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(padded, Radius.circular(radius)),
        Paint()..blendMode = BlendMode.clear,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      spotlightRect != old.spotlightRect;
}
