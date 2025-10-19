import 'dart:ui';

import 'package:flutter/material.dart';

import 'screens/ai_screen.dart';
import 'screens/bible_screen.dart';
import 'screens/home_screen.dart';
import 'screens/more_screen.dart';
import 'screens/notes_screen.dart';

void main() {
  runApp(const AgapeApp());
}

class AgapeApp extends StatefulWidget {
  const AgapeApp({super.key});

  @override
  State<AgapeApp> createState() => _AgapeAppState();
}

class _AgapeAppState extends State<AgapeApp> {
  int _selectedIndex = 0;
  bool _showBottomBar = true;
  ThemeMode _themeMode = ThemeMode.dark;
  int _aiActivationTick = 0;
  int _navVisibilityResetTick = 0;

  void _setBottomBarVisible(bool visible) {
    if (_showBottomBar != visible) {
      setState(() => _showBottomBar = visible);
    }
  }

  void _setDarkMode(bool enabled) {
    setState(() => _themeMode = enabled ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      BibleScreen(
        onScrollVisibilityChange: _setBottomBarVisible,
        navVisible: _showBottomBar,
        navVisibilityResetTick: _navVisibilityResetTick,
      ),
      AIScreen(
        onScrollVisibilityChange: _setBottomBarVisible,
        navVisible: _showBottomBar,
        activationTick: _aiActivationTick,
        navVisibilityResetTick: _navVisibilityResetTick,
      ),
      const NotesScreen(),
      MoreScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onDarkModeChanged: _setDarkMode,
      ),
    ];

    const seed = Color(0xFF1E88E5);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agape',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0B0F),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: Builder(
        builder: (context) {
          return Scaffold(
            extendBody: true,
            body: Stack(
              children: [
                Positioned.fill(child: screens[_selectedIndex]),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _showBottomBar
                        ? SafeArea(
                            key: const ValueKey('nav-overlay'),
                            top: false,
                            left: false,
                            right: false,
                            bottom: true,
                            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                              onQuickAction: () => setState(() {
                                _showBottomBar = true;
                                _selectedIndex = 4;
                                _navVisibilityResetTick++;
                              }),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('nav-hidden')),
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

class _IOSNavBar extends StatelessWidget {
  const _IOSNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.onQuickAction,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onQuickAction;

  static const List<_NavBarItem> _items = [
    _NavBarItem(icon: Icons.home_rounded, label: 'Home'),
    _NavBarItem(icon: Icons.menu_book_rounded, label: 'Bible'),
    _NavBarItem(icon: Icons.chat_bubble_rounded, label: 'Agape'),
    _NavBarItem(icon: Icons.note_alt_rounded, label: 'Notes'),
    _NavBarItem(icon: Icons.more_horiz_rounded, label: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final int activeIndex = currentIndex.clamp(0, _items.length - 1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _LiquidTabStrip(
        items: _items,
        activeIndex: activeIndex,
        showIndicator: true,
        onTap: onTap,
      ),
    );
  }
}

class _NavBarItem {
  const _NavBarItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
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

  static const double _barHeight = 58;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color baseColor = isDark
            ? const Color(0xFF242429).withOpacity(0.9)
            : scheme.surface.withOpacity(0.96);
        final Color borderColor = isDark ? Colors.white10 : Colors.black12.withOpacity(0.12);
        final Color shadowColor = Colors.black.withOpacity(isDark ? 0.48 : 0.18);

        return SizedBox(
          height: _barHeight,
          child: Stack(
            children: [
              // Single solid pill behind all 5 buttons
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: baseColor,
                      border: Border.all(color: borderColor, width: 0.7),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Buttons row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _LiquidNavDestination(
                          item: items[i],
                          index: i,
                          activeIndex: activeIndex,
                          showIndicator: showIndicator,
                          baseColor: baseColor,
                          onTap: () => onTap(i),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
    required this.baseColor,
  });

  final _NavBarItem item;
  final int index;
  final int? activeIndex;
  final bool showIndicator;
  final VoidCallback onTap;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool active = showIndicator && activeIndex == index;
    final bool isDark = scheme.brightness == Brightness.dark;
    final Color highlightOverlay = scheme.primary.withOpacity(isDark ? 0.22 : 0.16);
    final Color activeBackground = Color.alphaBlend(highlightOverlay, baseColor);
    final Color inactiveForeground =
        isDark ? Colors.white.withOpacity(0.82) : scheme.onSurface.withOpacity(0.72);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: active
            ? BoxDecoration(
                color: activeBackground,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.primary.withOpacity(isDark ? 0.35 : 0.22),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                    blurRadius: 9,
                    offset: const Offset(0, 5),
                  )
                ],
              )
            : const BoxDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 18,
              color: active
                  ? (isDark ? Colors.white : scheme.onPrimaryContainer)
                  : inactiveForeground,
            ),
            const SizedBox(height: 1.5),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 9.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.35,
                color: active
                    ? (isDark ? Colors.white.withOpacity(0.92) : scheme.onPrimaryContainer)
                    : (isDark
                        ? Colors.white.withOpacity(0.82)
                        : scheme.onSurfaceVariant.withOpacity(0.72)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavGlassBackground extends StatelessWidget {
  const _NavGlassBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isDark = scheme.brightness == Brightness.dark;
    final List<Color> gradientColors = isDark
        ? [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.02),
          ]
        : [
            color.withOpacity(0.92),
            color.withOpacity(0.78),
          ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(isDark ? 0.12 : 0.22),
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.07),
            blurRadius: isDark ? 18 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );
  }
}

// Quick-action button removed; More is now part of the main strip
