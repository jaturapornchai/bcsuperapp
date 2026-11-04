import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ChatRoomThemeMode {
  classicSky('classic_sky', 'LINE Classic Sky', Color(0xFF8CABD9), false),
  darkSlate('dark_slate', 'Executive Dark Slate', Color(0xFF0F172A), true),
  pearlMist('pearl_mist', 'Pearl Mist', Color(0xFFF1F5F9), false);

  final String code;
  final String label;
  final Color backgroundColor;
  final bool isDark;

  const ChatRoomThemeMode(
    this.code,
    this.label,
    this.backgroundColor,
    this.isDark,
  );

  static ChatRoomThemeMode fromCode(String? code) {
    for (final mode in ChatRoomThemeMode.values) {
      if (mode.code == code) return mode;
    }
    return ChatRoomThemeMode.classicSky;
  }
}

class AppTheme {
  // Primary LINE Emerald & Executive Slate Palette
  static const Color lineEmerald = Color(0xFF06C755);
  static const Color deepEmerald = Color(0xFF00A040);
  static const Color softEmerald = Color(0xFFE8FBF0);
  static const Color sentBubble = Color(0xFFA8F5B8);
  static const Color receivedBubble = Color(0xFFFFFFFF);

  static const Color slateDark = Color(0xFF0F172A);
  static const Color slateNavy = Color(0xFF1E293B);
  static const Color slateBody = Color(0xFF334155);
  static const Color slateMuted = Color(0xFF64748B);
  static const Color surfaceBg = Color(0xFFF4F6FA);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color borderSubtle = Color(0xFFE2E8F0);

  // Category & Accent Colors
  static const Color workBlue = Color(0xFF2563EB);
  static const Color personalPurple = Color(0xFF7C3AED);
  static const Color warningAmber = Color(0xFFD97706);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color goldPin = Color(0xFFF59E0B);

  static ThemeData buildTheme() {
    final baseText = GoogleFonts.promptTextTheme();

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surfaceBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lineEmerald,
        primary: lineEmerald,
        secondary: deepEmerald,
        surface: cardBg,
        onPrimary: Colors.white,
        onSurface: slateDark,
      ),
      textTheme: baseText.apply(
        bodyColor: slateDark,
        displayColor: slateDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: slateDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.prompt(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lineEmerald, width: 1.6),
        ),
        hintStyle: GoogleFonts.prompt(
          fontSize: 13.5,
          color: slateMuted,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lineEmerald,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.prompt(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: slateDark,
          minimumSize: const Size(0, 42),
          side: const BorderSide(color: borderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.prompt(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static Color parseHexColor(String? hex, {Color fallback = lineEmerald}) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final val = int.tryParse('FF$clean', radix: 16);
      if (val != null) return Color(val);
    } else if (clean.length == 8) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(val);
    }
    return fallback;
  }

  static IconData resolveMiniAppIcon(String? iconName) {
    switch (iconName) {
      case 'event_available':
      case 'calendar':
        return Icons.event_available_rounded;
      case 'description':
      case 'quote':
        return Icons.description_rounded;
      case 'receipt_long':
      case 'expense':
        return Icons.receipt_long_rounded;
      case 'schedule':
      case 'booking':
        return Icons.schedule_send_rounded;
      case 'inventory':
      case 'stock':
        return Icons.inventory_2_rounded;
      case 'support_agent':
        return Icons.support_agent_rounded;
      case 'analytics':
        return Icons.analytics_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }
}

/// Global Shared Avatar with online ring & fallback initials
class UserAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double radius;
  final bool showOnline;
  final bool isOfficial;
  final bool isGroup;

  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 22,
    this.showOnline = false,
    this.isOfficial = false,
    this.isGroup = false,
  });

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'BC';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0].characters.first}${parts[1].characters.first}'
          .toUpperCase();
    }
    return trimmed.characters.take(2).toString().toUpperCase();
  }

  List<Color> _gradientColors() {
    if (isOfficial) {
      return const [Color(0xFF06C755), Color(0xFF008F39)];
    }
    if (isGroup) {
      return const [Color(0xFF2563EB), Color(0xFF1D4ED8)];
    }
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    const palettes = [
      [Color(0xFF0EA5E9), Color(0xFF2563EB)],
      [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
      [Color(0xFFEC4899), Color(0xFFBE185D)],
      [Color(0xFF10B981), Color(0xFF047857)],
      [Color(0xFFF59E0B), Color(0xFFD97706)],
    ];
    return palettes[hash % palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradientColors();
    final hasImage =
        avatarUrl != null &&
        avatarUrl!.trim().isNotEmpty &&
        avatarUrl!.startsWith('http');

    return SizedBox(
      width: radius * 2 + 4,
      height: radius * 2 + 4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildFallback(),
                  )
                : _buildFallback(),
          ),
          if (showOnline)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: radius * 0.52,
                height: radius * 0.52,
                decoration: BoxDecoration(
                  color: AppTheme.lineEmerald,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          if (isOfficial && !showOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppTheme.lineEmerald,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Icon(
                  Icons.verified_rounded,
                  size: radius * 0.45,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallback() {
    if (isGroup) {
      return Center(
        child: Icon(
          Icons.groups_rounded,
          color: Colors.white,
          size: radius * 1.05,
        ),
      );
    }
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Global Baseline-Aligned Badge (Strict horizontal & vertical center alignment)
class PillBadge extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;

  const PillBadge({
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
