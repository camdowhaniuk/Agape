import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/verse_of_the_day_service.dart';
import '../widgets/verse_of_the_day_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onVerseOfTheDayTap,
    this.onScrollVisibilityChange,
  });

  final void Function(String book, int chapter, int verse)? onVerseOfTheDayTap;
  final void Function(bool)? onScrollVisibilityChange;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VerseOfTheDayService _verseService = VerseOfTheDayService.instance;
  final ScrollController _scrollController = ScrollController();
  DailyVerse? _todaysVerse;
  bool _loading = true;
  double _lastScrollOffset = 0.0;
  bool _navVisible = true;

  @override
  void initState() {
    super.initState();
    _loadVerse();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final currentOffset = _scrollController.offset;
    final scrollingDown = currentOffset > _lastScrollOffset;
    final scrollingUp = currentOffset < _lastScrollOffset;

    // Hide nav when scrolling down, show when scrolling up
    if (scrollingDown && currentOffset > 50) {
      _setNavVisible(false);
    } else if (scrollingUp || currentOffset <= 50) {
      _setNavVisible(true);
    }

    _lastScrollOffset = currentOffset;
  }

  void _setNavVisible(bool visible) {
    if (_navVisible == visible) return;
    setState(() {
      _navVisible = visible;
    });
    widget.onScrollVisibilityChange?.call(visible);
  }

  void _toggleNav() {
    _setNavVisible(!_navVisible);
  }

  Future<void> _loadVerse() async {
    final verse = await _verseService.getTodaysVerse();
    if (mounted) {
      setState(() {
        _todaysVerse = verse;
        _loading = false;
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }

  String _getFirstName(User? user) {
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      // Extract first name from display name
      final parts = user.displayName!.split(' ');
      return parts.first;
    }
    // Fallback to email prefix if no display name
    if (user?.email != null) {
      return user!.email!.split('@').first;
    }
    return 'Friend';
  }

  void _handleVerseOfTheDayTap() {
    if (_todaysVerse != null && widget.onVerseOfTheDayTap != null) {
      widget.onVerseOfTheDayTap!(
        _todaysVerse!.book,
        _todaysVerse!.chapter,
        _todaysVerse!.verse,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final greeting = _getGreeting();
    final firstName = _getFirstName(user);

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleNav,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24.0,
                MediaQuery.of(context).padding.top + 24.0,
                24.0,
                MediaQuery.of(context).padding.bottom + 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const SizedBox(height: 16),
              // Greeting
              Text(
                '$greeting,',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w300,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                firstName,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              // Verse of the Day
              if (_loading)
                const VerseOfTheDayCardLoading()
              else if (_todaysVerse != null)
                VerseOfTheDayCard(
                  verse: _todaysVerse!,
                  onVerseTap: _handleVerseOfTheDayTap,
                ),
              const SizedBox(height: 24),
              // Placeholder for future dashboard content
              Center(
                child: Text(
                  'More dashboard widgets coming soon...',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
