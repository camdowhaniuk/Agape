import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'widgets/auth_gate.dart';

// Screens
import 'screens/ai_screen.dart';
import 'screens/bible_screen.dart';
import 'screens/home_screen.dart';
import 'screens/more_screen.dart';
import 'screens/notes_screen.dart';

// Utils & Services
import 'services/highlight_service.dart';
import 'utils/scripture_reference.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AgapeApp());
}

// -----------------------------------------------------------------------------
// Root App
// -----------------------------------------------------------------------------
class AgapeApp extends StatelessWidget {
  const AgapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agape',
      themeMode: ThemeMode.dark,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const AuthGate(), // 🔥 decides between LoginScreen or AgapeMainShell
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: const Color(0xFFDC143C), // Crimson red
        secondary: const Color(0xFF8B0000), // Dark red
        surface: Colors.white,
        error: const Color(0xFFB00020),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.black,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFFFF4444), // Bright red
        secondary: const Color(0xFFCC0000), // Red
        surface: const Color(0xFF1A1A1A), // Very dark gray (almost black)
        error: const Color(0xFFCF6679),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onError: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Main Shell (your full navigation + screens)
// -----------------------------------------------------------------------------
class AgapeMainShell extends StatefulWidget {
  const AgapeMainShell({super.key});

  @override
  State<AgapeMainShell> createState() => _AgapeMainShellState();
}

class _AgapeMainShellState extends State<AgapeMainShell> {
  int _selectedIndex = 0;
  bool _showBottomBar = true;
  ThemeMode _themeMode = ThemeMode.dark;
  int _aiActivationTick = 0;
  int _navVisibilityResetTick = 0;
  String? _bibleInitialBook;
  int? _bibleInitialChapter;
  int? _bibleInitialVerse;
  int _bibleNavRequestKey = 0;

  void _setBottomBarVisible(bool visible) {
    if (_showBottomBar != visible) {
      setState(() => _showBottomBar = visible);
    }
  }

  void _setDarkMode(bool enabled) {
    setState(() => _themeMode = enabled ? ThemeMode.dark : ThemeMode.light);
  }

  void _openBibleAt({
    required String book,
    required int chapter,
    int? verse,
  }) {
    setState(() {
      _showBottomBar = true;
      _selectedIndex = 1;
      _navVisibilityResetTick++;
      _bibleInitialBook = book;
      _bibleInitialChapter = chapter;
      _bibleInitialVerse = verse;
      _bibleNavRequestKey++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _bibleInitialBook = null;
        _bibleInitialChapter = null;
        _bibleInitialVerse = null;
      });
    });
  }

  void _handleHighlightSelected(HighlightEntry entry) {
    _openBibleAt(
      book: entry.book,
      chapter: entry.chapter,
      verse: entry.verse,
    );
  }

  void _handleReferenceTap(ScriptureReference reference) {
    _openBibleAt(
      book: reference.book,
      chapter: reference.chapter,
      verse: reference.verse,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      BibleScreen(
        key: ValueKey<int>(_bibleNavRequestKey),
        onScrollVisibilityChange: _setBottomBarVisible,
        navVisible: _showBottomBar,
        navVisibilityResetTick: _navVisibilityResetTick,
        initialBook: _bibleInitialBook,
        initialChapter: _bibleInitialChapter,
        initialVerse: _bibleInitialVerse,
      ),
      AIScreen(
        onScrollVisibilityChange: _setBottomBarVisible,
        navVisible: _showBottomBar,
        activationTick: _aiActivationTick,
        navVisibilityResetTick: _navVisibilityResetTick,
        onReferenceTap: _handleReferenceTap,
      ),
      NotesScreen(
        onScrollVisibilityChange: _setBottomBarVisible,
        navVisible: _showBottomBar,
        navVisibilityResetTick: _navVisibilityResetTick,
        onHighlightSelected: _handleHighlightSelected,
      ),
      MoreScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onDarkModeChanged: _setDarkMode,
      ),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agape',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.light(
          primary: const Color(0xFFDC143C), // Crimson red
          secondary: const Color(0xFF8B0000), // Dark red
          surface: Colors.white,
          error: const Color(0xFFB00020),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.black,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFF4444), // Bright red
          secondary: const Color(0xFFCC0000), // Red
          surface: const Color(0xFF1A1A1A), // Very dark gray (almost black)
          error: const Color(0xFFCF6679),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onError: Colors.black,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          final double safeBottom = media.padding.bottom;
          final double safeLeft = media.padding.left;
          final double safeRight = media.padding.right;
          final double navBottomGap = (safeBottom * 0.5) + 6;
          final EdgeInsets navPadding = EdgeInsets.fromLTRB(
            20 + safeLeft,
            0,
            20 + safeRight,
            navBottomGap,
          );

          return Scaffold(
            extendBody: true,
            body: Stack(
              children: [
                Positioned.fill(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: screens,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: navPadding,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _IOSNavBar(
                            currentIndex: _selectedIndex,
                            onTap: (index) {
                              if (index == 2) {
                                setState(() {
                                  _showBottomBar = true;
                                  _selectedIndex = index;
                                  _aiActivationTick++;
                                  _navVisibilityResetTick++;
                                });
                              } else {
                                setState(() {
                                  _showBottomBar = true;
                                  _selectedIndex = index;
                                  _navVisibilityResetTick++;
                                });
                              }
                            },
                            visible: _showBottomBar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Navigation Bar Widgets (unchanged from your version)
// -----------------------------------------------------------------------------
class _IOSNavBar extends StatelessWidget {
  const _IOSNavBar({
    required this.currentIndex,
    required this.onTap,
    this.visible = true,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool visible;

  static const List<_NavBarItem> _items = [
    _NavBarItem(icon: Icons.home_rounded, label: 'Home'),
    _NavBarItem(icon: Icons.menu_book_rounded, label: 'Bible'),
    _NavBarItem(icon: Icons.chat_bubble_rounded, label: 'Agape'),
    _NavBarItem(icon: Icons.note_alt_rounded, label: 'Notes'),
    _NavBarItem(
      icon: Icons.more_horiz_rounded,
      label: 'More',
      accentIcon: Icons.highlight_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final int activeIndex = currentIndex.clamp(0, _items.length - 1);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : const Offset(0, 0.25),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  offset: const Offset(0, 8),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    // Much more transparent for true glassmorphism
                    color: const Color(0xFF1C1C1E).withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: _LiquidTabStrip(
                      items: _items,
                      activeIndex: activeIndex,
                      showIndicator: true,
                      onTap: onTap,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem {
  const _NavBarItem({
    required this.icon,
    required this.label,
    this.accentIcon,
  });

  final IconData icon;
  final String label;
  final IconData? accentIcon;
}

class _LiquidTabStrip extends StatelessWidget {
  const _LiquidTabStrip({
    required this.items,
    required this.activeIndex,
    required this.showIndicator,
    required this.onTap,
  });

  final List<_NavBarItem> items;
  final int? activeIndex;
  final bool showIndicator;
  final ValueChanged<int> onTap;

  static const double _barHeight = 60;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: _barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _LiquidNavDestination(
                      item: items[i],
                      index: i,
                      activeIndex: activeIndex,
                      showIndicator: showIndicator,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiquidNavDestination extends StatelessWidget {
  const _LiquidNavDestination({
    required this.item,
    required this.index,
    required this.activeIndex,
    required this.showIndicator,
    required this.onTap,
  });

  final _NavBarItem item;
  final int index;
  final int? activeIndex;
  final bool showIndicator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool active = showIndicator && activeIndex == index;

    // Apple Books exact colors from screenshot
    final Color inactiveForeground = const Color(0xFFBBBBBB); // Light gray/white for inactive
    final Color activeForeground = const Color(0xFF2C2C2E); // Dark gray for active text/icon

    // Light beige/cream pill matching Apple Books "Home" tab
    final Color activePillColor = const Color(0xFFB5A89A); // Light beige/cream

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: active
            ? BoxDecoration(
                color: activePillColor,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    spreadRadius: 0,
                    offset: const Offset(0, 1),
                  ),
                ],
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 24,
              color: active ? activeForeground : inactiveForeground,
              weight: active ? 500 : 400,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                height: 1.2,
                color: active ? activeForeground : inactiveForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
