import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'constants/colors.dart';
import 'screens/home_screen.dart';
import 'services/theme_provider.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

void main() {
  // Make all debug prints works on debug mode only
  debugPrint = (String? message, {int? wrapWidth}) {
    if (kDebugMode) {
      developer.log(message ?? '', name: 'SWAP');
    }
  };

  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const SwappedApp(),
    ),
  );
}

class SwappedApp extends StatelessWidget {
  const SwappedApp({super.key});
  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        // Update system UI overlay for current theme
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            systemNavigationBarIconBrightness: themeProvider.isDarkMode
                ? Brightness.light
                : Brightness.dark,
            statusBarIconBrightness: themeProvider.isDarkMode
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: themeProvider.isDarkMode
                ? Brightness.dark
                : Brightness.light,
          ),
        );
        return MaterialApp(
          title: 'SWAPPED',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.mainBg,
            fontFamily: GoogleFonts.inter().fontFamily,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            scaffoldBackgroundColor: AppColors.mainBg,
            fontFamily: GoogleFonts.inter().fontFamily,
            brightness: Brightness.dark,
          ),
          themeMode: themeProvider.isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light,
          // Limit text scaling to prevent UI breakage on large font devices
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final clampedTextScaler = mediaQuery.textScaler.clamp(
              minScaleFactor: 1,
              maxScaleFactor: 1,
            );
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: clampedTextScaler),
              child: child!,
            );
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}
