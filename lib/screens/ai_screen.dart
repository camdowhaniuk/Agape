import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../services/ai_conversation.dart';
import '../services/ai_conversation_store.dart';
import '../services/ai_service.dart';
import '../services/user_state_service.dart';
import '../utils/scripture_reference.dart';
import 'bible_screen.dart';
import '../widgets/app_logo.dart';
import '../widgets/markdown_message.dart';

class AIScreen extends StatefulWidget {
  const AIScreen({
    super.key,
    this.onScrollVisibilityChange,
    this.navVisible = true,
    this.activationTick = 0,
    this.navVisibilityResetTick = 0,
    this.onReferenceTap,
  });

  final void Function(bool)? onScrollVisibilityChange;
  final bool navVisible;
  final int activationTick;
  final int navVisibilityResetTick;
  final void Function(ScriptureReference reference)? onReferenceTap;

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  static const String _assistantName = 'Agape';
  static const double _navOverlayHeight = 72;
  static const String _lastConversationStorageKey = 'ai.lastConversationId';
  static const String _streamingFallbackMessage =
      'I was unable to generate a response this time. Would you try again?';

  static const String _systemPrompt =
      'You are the absolute best Bible theologian-teacher. Interpret Scripture with humility, '
      'historic orthodox faith, and a Christ-centered lens (Luke 24:27). '
      'Treat the Bible as the Word of God revealing Jesus the Son of God. '
      'Prefer Scripture to speculation. Cite passages naturally. Be pastoral, clear, and concise while also remaining friendly.'
      'Reflect the character of Jesus in your words. Full of grace and truth. '
      'Your name is Agape to bring reverance to the love of Jesus Christ that surpasses all knowledge. '
      'Reflect the wisdom of Jesus in your answers. '
      'You have no authority in your teachings, only point to what the Bible says';

  late final AIService _service = AIService(systemPrompt: _systemPrompt);
  final AIConversationStore _store = AIConversationStore();
  final UserStateService _userStateService = UserStateService.instance;
  final List<AIMessage> _messages = [];
  List<AIConversation> _conversations = const <AIConversation>[];
  String? _activeConversationId;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  bool _sending = false;
  bool _streaming = false;
  Timer? _streamUpdateTimer;
  String? _streamingMessageId;
  bool _shouldAutoScrollToBottom = false;
  bool _chromeVisible = true;
  bool _adjustingChromeScroll = false;
  bool _navVisibilityArmed = false;
  bool _navVisibilityPrimed = false;
  double? _lastScrollOffset;
  bool _pendingEnsureBottom = false;
  int _ensureBottomAttempts = 0;
  final GlobalKey _bottomAnchorKey = GlobalKey();
  double? _lastObservedMaxExtent;
  bool _navRevealSuppressed = false;
  bool _composerFocused = false;
  double? _cachedBottomPadding;
  double? _cachedTopPadding;

  @override
  void initState() {
    super.initState();
    _navVisibilityPrimed = true;
    _loadConversations();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _service.dispose();
    _streamUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final conversations = await _store.loadAll();
    final storedId = (await _userStateService.readString(
      _lastConversationStorageKey,
    ))?.trim();
    final preferId = (storedId != null && storedId.isNotEmpty)
        ? storedId
        : _activeConversationId;
    if (!mounted) return;
    if (conversations.isEmpty) {
      final created = await _store.create();
      if (!mounted) return;
      setState(() {
        _conversations = <AIConversation>[created];
        _activeConversationId = created.id;
        _messages
          ..clear()
          ..addAll(created.messages);
      });
      await _persistLastConversationId(created.id);
      return;
    }
    final active = _resolveActive(conversations, preferId: preferId);
    debugPrint('[AIScreen] _loadConversations -> activeId=${active?.id} shouldAuto=$_shouldAutoScrollToBottom pending=$_pendingEnsureBottom');
    setState(() {
      _conversations = conversations;
      _activeConversationId = active?.id;
      _messages
        ..clear()
        ..addAll(active?.messages ?? const <AIMessage>[]);
    });
    if (active != null) {
      await _persistLastConversationId(active.id);
    }
    if (_messages.isNotEmpty) {
      // Add delay to ensure ListView is built and attached before scrolling
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          debugPrint('[AIScreen] _loadConversations schedule ensure bottom shouldAuto before=$_shouldAutoScrollToBottom pending=$_pendingEnsureBottom');
          _shouldAutoScrollToBottom = true;
          _requestEnsureBottom(force: true);
          _jumpToBottomSoon();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted || !_scroll.hasClients) return;
            final position = _scroll.position;
            final distance = position.maxScrollExtent - position.pixels;
            if (distance > 32) {
              debugPrint('[AIScreen] second pass auto-scroll distance=$distance');
              _shouldAutoScrollToBottom = true;
              _requestEnsureBottom(force: true);
              _jumpToBottomSoon();
            }
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant AIScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activationTick != oldWidget.activationTick) {
      _scrollToBottomFromNav();
    }
    if (widget.navVisibilityResetTick != oldWidget.navVisibilityResetTick) {
      _resetNavVisibilityArming();
      if (!_chromeVisible) {
        _setChromeVisible(true, force: true);
      }
    }
  }

  AIConversation? _resolveActive(
    List<AIConversation> conversations, {
    String? preferId,
  }) {
    if (conversations.isEmpty) return null;
    if (preferId != null) {
      for (final convo in conversations) {
        if (convo.id == preferId) return convo;
      }
    }
    return conversations.first;
  }

  Future<void> _persistLastConversationId(String id) {
    if (id.isEmpty) return Future.value();
    return _userStateService.writeString(_lastConversationStorageKey, id);
  }

  Future<void> _persistActiveConversation() async {
    final messages = List<AIMessage>.from(_messages);
    final activeId = _activeConversationId;
    AIConversation? activeConversation;
    if (activeId != null) {
      for (final convo in _conversations) {
        if (convo.id == activeId) {
          activeConversation = convo;
          break;
        }
      }
    }

    if (activeConversation == null) {
      final created = await _store.create(messages: messages);
      await _refreshConversations(preferId: created.id);
      return;
    }

    final now = DateTime.now();
    final updated = activeConversation.copyWith(
      messages: messages,
      updatedAt: messages.isNotEmpty ? messages.last.timestamp : now,
      createdAt: activeConversation.createdAt,
    );
    await _store.upsert(updated);
    await _refreshConversations(preferId: updated.id);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();

    // Cache current padding values before streaming starts
    // This prevents scroll jumps when padding recalculates
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final keyboardInset = media.viewInsets.bottom;
    final navAwarePadding = widget.navVisible
        ? _navOverlayHeight + (bottomInset * 0.5 + 6)
        : bottomInset;
    const floatingComposerHeight = 58.0;
    final showComposer =
        _composerFocused || _chromeVisible || keyboardInset > 0;

    _cachedBottomPadding = keyboardInset > 0
        ? keyboardInset + floatingComposerHeight + 16
        : (showComposer
              ? (widget.navVisible ? navAwarePadding : bottomInset) +
                    floatingComposerHeight +
                    6
              : bottomInset + 10);
    _cachedTopPadding = media.padding.top + (_chromeVisible ? 86 : 48);

    final userMessage = AIMessage(role: AIRole.user, content: text);
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _streaming = true;
      _controller.clear();
    });
    _jumpToBottomSoon();
    await _persistActiveConversation();

    final history = List<AIMessage>.from(_messages);
    final assistantPlaceholder = AIMessage(role: AIRole.assistant, content: '');
    final placeholderId = assistantPlaceholder.timestamp.toIso8601String();
    setState(() {
      _messages.add(assistantPlaceholder);
      _streamingMessageId = placeholderId;
    });

    String accumulatedText = '';
    var receivedContent = false;

    void scheduleStreamingUpdate() {
      if (!mounted) return;
      if (_streamUpdateTimer?.isActive ?? false) return;
      _streamUpdateTimer = Timer(const Duration(milliseconds: 16), () {
        if (!mounted) return;
        setState(() {});
        // Don't auto-scroll during streaming - let user control their position
        _streamUpdateTimer = null;
      });
    }

    void updateStreamingMessage(String content) {
      final index = _messages.indexWhere(
        (m) => m.timestamp.toIso8601String() == placeholderId,
      );
      if (index == -1) return;
      final existing = _messages[index];
      _messages[index] = AIMessage(
        role: existing.role,
        content: content,
        timestamp: existing.timestamp,
      );
      scheduleStreamingUpdate();
    }

    try {
      await for (final chunk in _service.replyStream(
        history: history,
        userMessage: text,
      )) {
        accumulatedText += chunk;
        receivedContent = true;
        updateStreamingMessage(accumulatedText);
      }

      final trimmed = accumulatedText.trim();
      final needsFallback =
          !receivedContent ||
          trimmed.isEmpty ||
          trimmed == _streamingFallbackMessage;

      if (needsFallback) {
        try {
          final fallbackReply = await _service.reply(
            history: history,
            userMessage: text,
          );
          final fallbackText = fallbackReply.trim();
          if (fallbackText.isNotEmpty) {
            accumulatedText = fallbackText;
            receivedContent = true;
            updateStreamingMessage(fallbackText);
          } else if (!receivedContent) {
            updateStreamingMessage(_streamingFallbackMessage);
          }
        } catch (error) {
          debugPrint('AI fallback reply failed: $error');
          updateStreamingMessage(
            error is AIServiceAuthException
                ? 'I need your Gemini API key before I can respond. Launch the app with '
                      '--dart-define=GEMINI_API_KEY=your_key and try again.'
                : 'I ran into a problem replying just now. Would you try again? (Error: $error)',
          );
        }
      }

      _streamUpdateTimer?.cancel();
      if (mounted) {
        setState(() {});
      }
      await _persistActiveConversation();
    } catch (error) {
      debugPrint('AI reply failed: $error');
      final bool authError = error is AIServiceAuthException;
      updateStreamingMessage(
        authError
            ? 'I need your Gemini API key before I can respond. Launch the app with '
                  '--dart-define=GEMINI_API_KEY=your_key and try again.'
            : 'I ran into a problem replying just now. Would you try again? (Error: $error)',
      );
      _streamUpdateTimer?.cancel();
      if (mounted) {
        setState(() {});
      }
      await _persistActiveConversation();
    } finally {
      _streamUpdateTimer?.cancel();
      _streamUpdateTimer = null;
      _streamingMessageId = null;
      if (mounted) {
        setState(() {
          _sending = false;
          _streaming = false;
        });
        // Clear padding cache after a delay to ensure smooth transition
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _cachedBottomPadding = null;
              _cachedTopPadding = null;
            });
          }
        });
      } else {
        _sending = false;
        _streaming = false;
        _cachedBottomPadding = null;
        _cachedTopPadding = null;
      }
      // Don't auto-scroll after streaming - let user stay where they are reading
    }
  }

  Future<void> _newChat() async {
    final created = await _store.create();
    await _refreshConversations(preferId: created.id);
  }

  void _jumpToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final media = MediaQuery.of(context);
      final bottomPadding = media.padding.bottom;
      final navPadding = widget.navVisible ? _navOverlayHeight : 0;
      final target = position.maxScrollExtent + bottomPadding + navPadding + 8;
      position.animateTo(
        target.clamp(0.0, target),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
    // Don't use _requestEnsureBottom() - it causes aggressive scroll jumps
    // The animateTo above is sufficient for sending messages
  }

  void _handleComposerFocus(bool focused) {
    if (!mounted) return;
    setState(() {
      _composerFocused = focused;
      _navRevealSuppressed = focused;
    });
    if (focused) {
      _setChromeVisible(false, force: true);
    } else {
      final bottomReached =
          _scroll.hasClients &&
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 4;
      if (bottomReached) {
        _setChromeVisible(false, force: true);
      } else {
        _setChromeVisible(true);
      }
    }
  }

  void _resetNavVisibilityArming() {
    _navVisibilityArmed = false;
    _navVisibilityPrimed = true;
  }

  void _scrollToBottomFromNav() {
    _setChromeVisible(true);
    debugPrint('[AIScreen] _scrollToBottomFromNav shouldAuto=$_shouldAutoScrollToBottom pending=$_pendingEnsureBottom');
    if (_messages.isEmpty) return;
    if (!_shouldAutoScrollToBottom && !_pendingEnsureBottom) {
      debugPrint(
        '[AIScreen] _scrollToBottomFromNav skipped (shouldAuto=$_shouldAutoScrollToBottom pending=$_pendingEnsureBottom)',
      );
      return;
    }
    _requestEnsureBottom(force: _shouldAutoScrollToBottom);
  }

  void _requestEnsureBottom({bool force = false}) {
    if (_messages.isEmpty) {
      debugPrint('[AIScreen] _requestEnsureBottom aborted (no messages)');
      _pendingEnsureBottom = false;
      return;
    }
    if (!force && !_shouldAutoScrollToBottom) {
      debugPrint(
        '[AIScreen] _requestEnsureBottom skipped (shouldAutoScroll=$_shouldAutoScrollToBottom)',
      );
      return;
    }
    if (_pendingEnsureBottom) {
      debugPrint('[AIScreen] _requestEnsureBottom already pending shouldAuto=$_shouldAutoScrollToBottom');
      return;
    }
    debugPrint('[AIScreen] _requestEnsureBottom start force=$force shouldAuto=$_shouldAutoScrollToBottom');
    _pendingEnsureBottom = true;
    _ensureBottomAttempts = 0;
    _lastObservedMaxExtent = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureBottomVisible());
  }

  void _ensureBottomVisible() {
    if (!_pendingEnsureBottom) return;
    if (!mounted) {
      _pendingEnsureBottom = false;
      return;
    }
    final anchorContext = _bottomAnchorKey.currentContext;
    if (!_scroll.hasClients) {
      debugPrint(
        '[AIScreen] _ensureBottomVisible attempt=$_ensureBottomAttempts anchorCtx=$anchorContext hasClients=${_scroll.hasClients}',
      );
      if (_ensureBottomAttempts++ < 60) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureBottomVisible(),
        );
      } else {
        _pendingEnsureBottom = false;
        debugPrint('[AIScreen] _ensureBottomVisible giving up (no scroll clients)');
      }
      return;
    }
    final position = _scroll.position;
    if (!position.hasContentDimensions) {
      debugPrint(
        '[AIScreen] _ensureBottomVisible attempt=$_ensureBottomAttempts waiting for dimensions anchorCtx=$anchorContext',
      );
      if (_ensureBottomAttempts++ < 60) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureBottomVisible(),
        );
      } else {
        _pendingEnsureBottom = false;
        debugPrint('[AIScreen] _ensureBottomVisible giving up (no dimensions)');
      }
      return;
    }
    final previousMax = _lastObservedMaxExtent;
    final currentMax = position.maxScrollExtent;
    if (currentMax <= 0) {
      debugPrint(
        '[AIScreen] _ensureBottomVisible attempt=$_ensureBottomAttempts maxScroll=0',
      );
      if (_ensureBottomAttempts++ < 60) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureBottomVisible(),
        );
      } else {
        _pendingEnsureBottom = false;
        debugPrint('[AIScreen] _ensureBottomVisible giving up (maxScroll<=0)');
      }
      return;
    }
    if (previousMax == null || (currentMax - previousMax).abs() > 1.0) {
      _lastObservedMaxExtent = currentMax;
      debugPrint(
        '[AIScreen] _ensureBottomVisible attempt=$_ensureBottomAttempts waiting for settle current=$currentMax previous=$previousMax',
      );
      if (_ensureBottomAttempts++ < 60) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureBottomVisible(),
        );
      } else {
        _pendingEnsureBottom = false;
        debugPrint('[AIScreen] _ensureBottomVisible giving up (never settled)');
      }
      return;
    }
    _pendingEnsureBottom = false;
    _lastObservedMaxExtent = null;
    _ensureBottomAttempts = 0;
    _shouldAutoScrollToBottom = false;
    final mediaContext = anchorContext ?? context;
    final bottomPadding = MediaQuery.of(mediaContext).padding.bottom;
    final navPadding = widget.navVisible ? _navOverlayHeight : 0;
    final extra = bottomPadding + navPadding + 8;
    debugPrint(
      '[AIScreen] _ensureBottomVisible jumpTo max=$currentMax extra=$extra',
    );
    final target = currentMax <= 0 ? 0.0 : currentMax;
    debugPrint('[AIScreen] _ensureBottomVisible jumping to $target (max=$currentMax) currentOffset=${position.pixels}');
    position.jumpTo(target);
    debugPrint('[AIScreen] _ensureBottomVisible after jump offset=${position.pixels} shouldAuto=$_shouldAutoScrollToBottom pending=$_pendingEnsureBottom');
  }

  Future<void> _refreshConversations({
    String? preferId,
    bool autoScroll = false,
  }) async {
    final conversations = await _store.loadAll();
    if (!mounted) return;
    final active = _resolveActive(conversations, preferId: preferId);
    setState(() {
      _conversations = conversations;
      _activeConversationId = active?.id;
      _messages
        ..clear()
        ..addAll(active?.messages ?? const <AIMessage>[]);
    });
    if (active != null) {
      await _persistLastConversationId(active.id);
    }
    if (_messages.isNotEmpty) {
      // Add delay to ensure ListView is built and attached before scrolling
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && autoScroll) {
          _shouldAutoScrollToBottom = true;
          _requestEnsureBottom(force: true);
          _jumpToBottomSoon();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted || !_scroll.hasClients) return;
            final position = _scroll.position;
            final distance = position.maxScrollExtent - position.pixels;
            if (distance > 32) {
              debugPrint('[AIScreen] second pass auto-scroll (refresh) distance=$distance');
              _shouldAutoScrollToBottom = true;
              _requestEnsureBottom(force: true);
              _jumpToBottomSoon();
            }
          });
        }
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (!_navVisibilityArmed) {
      if (_navVisibilityPrimed &&
          notification is UserScrollNotification &&
          notification.direction != ScrollDirection.idle) {
        _navVisibilityArmed = true;
      }
      _lastScrollOffset = notification.metrics.pixels;
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (delta < -6) {
        _setChromeVisible(true);
      } else if (delta > 6) {
        _setChromeVisible(false);
      }
      _lastScrollOffset = notification.metrics.pixels;
    } else if (notification is ScrollEndNotification) {
      _lastScrollOffset = notification.metrics.pixels;
    }
    return false;
  }

  void _setChromeVisible(bool visible, {bool force = false}) {
    if (!force && _navRevealSuppressed && visible) {
      return;
    }

    if (_cachedTopPadding == null) {
      _cachedTopPadding = _computeListTopPadding(chromeVisible: _chromeVisible);
    }
    if (_cachedBottomPadding == null) {
      _cachedBottomPadding =
          _computeListBottomPadding(chromeVisible: _chromeVisible);
    }

    if (_chromeVisible == visible) {
      if (force && visible) {
        _resetNavVisibilityArming();
      }
      return;
    }
    setState(() => _chromeVisible = visible);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cachedTopPadding = null;
      _cachedBottomPadding = null;
    });
    if (force && visible) {
      _resetNavVisibilityArming();
    }
    widget.onScrollVisibilityChange?.call(visible);
  }

  void _toggleChrome() {
    _setChromeVisible(!_chromeVisible, force: true);
  }

  double _computeListTopPadding({required bool chromeVisible}) {
    final media = MediaQuery.of(context);
    if (_cachedTopPadding != null && (_streaming || _sending)) {
      return _cachedTopPadding!;
    }
    return media.padding.top + (chromeVisible ? 86 : 48);
  }

  double _computeListBottomPadding({required bool chromeVisible}) {
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final keyboardInset = media.viewInsets.bottom;
    final navBottomPadding = bottomInset * 0.5 + 6;
    const floatingComposerHeight = 58.0;
    final showComposer = _composerFocused || chromeVisible || keyboardInset > 0;

    if (_cachedBottomPadding != null && (_streaming || _sending)) {
      return _cachedBottomPadding!;
    }
    if (keyboardInset > 0) {
      return keyboardInset + floatingComposerHeight + 16;
    }

    if (showComposer) {
      final navAwarePadding = widget.navVisible
          ? _navOverlayHeight + navBottomPadding
          : bottomInset;
      final base = widget.navVisible ? navAwarePadding : bottomInset;
      return base + floatingComposerHeight + 6;
    }

    return bottomInset + 10;
  }

  Future<void> _selectConversation(String id) async {
    if (_activeConversationId == id) return;
    await _refreshConversations(preferId: id);
  }

  Future<void> _renameConversation(AIConversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename chat'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Enter a new name',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newName == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == conversation.title) return;
    final updated = conversation.copyWith(
      title: trimmed,
      updatedAt: DateTime.now(),
    );
    await _store.upsert(updated);
    await _refreshConversations(preferId: updated.id);
  }

  Future<void> _deleteConversation(AIConversation conversation) async {
    if (_conversations.length <= 1) {
      await _store.clearAll();
      final created = await _store.create();
      await _refreshConversations(preferId: created.id);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete chat?'),
          content: const Text('This conversation will be removed permanently.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await _store.delete(conversation.id);
    await _refreshConversations(
      preferId: _activeConversationId == conversation.id
          ? null
          : _activeConversationId,
    );
  }

  Future<void> _showConversationPicker() async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            void refreshSheet() {
              modalSetState(() {});
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        height: 4,
                        width: 42,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Saved chats',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _newChat();
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('New chat'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_conversations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Start a conversation to save it here.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.6),
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: theme.dividerColor.withOpacity(0.1),
                          ),
                          itemBuilder: (context, index) {
                            final conversation = _conversations[index];
                            final isActive =
                                conversation.id == _activeConversationId;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              selected: isActive,
                              selectedTileColor: theme.colorScheme.primary
                                  .withOpacity(
                                    theme.brightness == Brightness.dark
                                        ? 0.12
                                        : 0.08,
                                  ),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: theme
                                    .colorScheme
                                    .primaryContainer
                                    .withOpacity(isActive ? 0.9 : 0.6),
                                child: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              title: Text(
                                conversation.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '${_formatTimestamp(context, conversation.updatedAt)} • ${_conversationPreview(conversation)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.65),
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'More actions',
                                onSelected: (value) async {
                                  if (value == 'rename') {
                                    await _renameConversation(conversation);
                                  } else if (value == 'delete') {
                                    await _deleteConversation(conversation);
                                  }
                                  refreshSheet();
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _selectConversation(conversation.id);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _conversationPreview(AIConversation conversation) {
    if (conversation.messages.isEmpty) {
      return 'No messages yet';
    }
    final latest = conversation.messages.last;
    final content = latest.content.trim();
    if (content.isEmpty) return 'No messages yet';
    final compact = content.replaceAll(RegExp(r'\s+'), ' ');
    return compact.length > 54 ? '${compact.substring(0, 54)}…' : compact;
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final date = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;
    final timeOfDay = TimeOfDay.fromDateTime(timestamp);
    final timeLabel = localizations.formatTimeOfDay(timeOfDay);
    if (difference == 0) return 'Today • $timeLabel';
    if (difference == 1) return 'Yesterday • $timeLabel';
    return '${timestamp.month}/${timestamp.day}/${timestamp.year} • $timeLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final media = MediaQuery.of(context);
    final double bottomInset = media.padding.bottom;
    final double navBottomPadding = bottomInset * 0.5 + 6;
    final double keyboardInset = media.viewInsets.bottom;
    final double navPadding = widget.navVisible ? _navOverlayHeight : 0;
    final double navAwarePadding = widget.navVisible
        ? _navOverlayHeight + navBottomPadding
        : bottomInset;
    const double floatingComposerHeight = 58;
    final bool showComposer =
        _composerFocused || _chromeVisible || keyboardInset > 0;
    final double composerBottomInset = keyboardInset > 0
        ? keyboardInset + 8
        : (widget.navVisible ? navAwarePadding + 4 : bottomInset + 8);
    // Use cached padding during and shortly after streaming to prevent scroll jumps
    final double listBottomPadding;
    if (_cachedBottomPadding != null && (_streaming || _sending)) {
      listBottomPadding = _cachedBottomPadding!;
    } else if (keyboardInset > 0) {
      listBottomPadding = keyboardInset + floatingComposerHeight + 16;
    } else if (showComposer) {
      listBottomPadding =
          (widget.navVisible ? navAwarePadding : bottomInset) +
          floatingComposerHeight +
          6;
    } else {
      listBottomPadding = bottomInset + 10;
    }

    final double listTopPadding =
        (_cachedTopPadding != null && (_streaming || _sending))
        ? _cachedTopPadding!
        : media.padding.top + (_chromeVisible ? 86 : 48);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: _toggleChrome,
              child: _buildChatBody(
                bottomPadding: listBottomPadding,
                topPadding: listTopPadding,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(12, 0, 12, composerBottomInset),
              child: IgnorePointer(
                ignoring: !showComposer && keyboardInset <= 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  offset: showComposer ? Offset.zero : const Offset(0, 0.25),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    opacity: showComposer ? 1 : 0,
                    child: _FloatingComposer(
                      controller: _controller,
                      isDark: isDark,
                      sending: _sending,
                      onSend: _send,
                      onFocusChange: _handleComposerFocus,
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            left: 12,
            right: 12,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: _chromeVisible
                ? media.padding.top + 8
                : media.padding.top - 72,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Row(
                  children: [
                    _SurfaceIconButton(
                      tooltip: 'Saved chats',
                      onPressed: _showConversationPicker,
                      icon: Icons.menu_rounded,
                    ),
                    const Spacer(),
                    _SurfaceIconButton(
                      tooltip: 'New chat',
                      onPressed: _newChat,
                      icon: Icons.add_comment_rounded,
                      crimson: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBody({
    required double bottomPadding,
    required double topPadding,
  }) {
    if (_messages.isEmpty) {
      return NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: _EmptyChat(
          assistantName: _assistantName,
          onPick: (q) {
            _controller.text = q;
            _send();
          },
          bottomPadding: bottomPadding,
          topPadding: topPadding,
        ),
      );
    }

    final bool includeIntro = true;
    final int messageStartIndex = includeIntro ? 1 : 0;
    final int totalCount = _messages.length + messageStartIndex;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
        itemCount: totalCount + 1,
        itemBuilder: (context, index) {
          if (index == totalCount) {
            return SizedBox(key: _bottomAnchorKey, height: 1);
          }
          if (includeIntro && index == 0) {
            return _ChatIntroBanner(
              assistantName: _assistantName,
              onSavedChatsTap: _showConversationPicker,
            );
          }

          final messageIndex = index - messageStartIndex;
          final m = _messages[messageIndex];
          final isLastMessage = messageIndex == _messages.length - 1;
          final isStreamingThisMessage =
              _streaming && isLastMessage && m.role == AIRole.assistant;

          // Use different widgets for user vs assistant messages
          if (m.role == AIRole.user) {
            return _UserMessageBubble(
              content: m.content,
              timestamp: m.timestamp,
            );
          } else {
            return _AssistantMessage(
              content: m.content,
              timestamp: m.timestamp,
              assistantName: _assistantName,
              onReferenceTap: widget.onReferenceTap,
              isStreaming: isStreamingThisMessage,
            );
          }
        },
      ),
    );
  }
}

class _FloatingComposer extends StatefulWidget {
  const _FloatingComposer({
    required this.controller,
    required this.onSend,
    required this.sending,
    required this.isDark,
    this.onFocusChange,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;
  final bool isDark;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<_FloatingComposer> createState() => _FloatingComposerState();
}

class _FloatingComposerState extends State<_FloatingComposer> {
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    widget.onFocusChange?.call(_focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color buttonColor = scheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
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
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFF1C1C1E).withValues(alpha: 0.2),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _focusNode,
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                    decoration: InputDecoration(
                      hintText: "What's on your mind?",
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.55,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 44,
                  width: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    onPressed: widget.sending ? null : widget.onSend,
                    child: widget.sending
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: theme.colorScheme.onPrimary,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SurfaceIconButton extends StatelessWidget {
  const _SurfaceIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.crimson = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;
  final bool crimson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final BorderRadius radius = BorderRadius.circular(20);
    final Color iconColor = crimson
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
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
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: const Color(0xFF1C1C1E).withValues(alpha: 0.2),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
              child: IconButton(
                tooltip: tooltip,
                iconSize: 22,
                color: iconColor,
                onPressed: onPressed,
                icon: Icon(icon),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({
    required this.content,
    required this.timestamp,
    required this.assistantName,
    this.onReferenceTap,
    this.isStreaming = false,
  });

  final String content;
  final DateTime timestamp;
  final String assistantName;
  final void Function(ScriptureReference reference)? onReferenceTap;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white.withOpacity(0.95) : Colors.black87;
    final meta = TimeOfDay.fromDateTime(timestamp).format(context);

    void openReference(ScriptureReference ref) {
      final handler = onReferenceTap;
      if (handler != null) {
        handler(ref);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _BibleReferencePage(reference: ref)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Agape name with icon (no background)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: isDark ? Colors.white70 : const Color(0xFF7954B1),
                ),
                const SizedBox(width: 6),
                Text(
                  assistantName,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w600,
                    color: textColor.withOpacity(isDark ? 0.9 : 0.78),
                  ),
                ),
              ],
            ),
          ),
          // Message content - full width with left padding, NO background
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: MarkdownMessage(
              markdown: content,
              baseStyle: TextStyle(
                height: 1.52,
                fontSize: 16.5,
                color: textColor,
                letterSpacing: 0.15,
              ),
              isDark: isDark,
              linkColor: theme.colorScheme.primary,
              onScriptureTap: openReference,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8),
            child: SizedBox(
              height: 24,
              child: isStreaming
                  ? const _BlinkingLogo()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: (isDark ? Colors.white70 : Colors.black54)
                              .withOpacity(0.7),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({required this.content, required this.timestamp});

  final String content;
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2B2B30) : const Color(0xFFE8E8ED);
    final fg = isDark ? Colors.white : Colors.black87;
    final meta = TimeOfDay.fromDateTime(timestamp).format(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 640),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
                width: 0.6,
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              content,
              style: TextStyle(
                height: 1.48,
                fontSize: 15.5,
                color: fg,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: (isDark ? Colors.white70 : Colors.black54).withOpacity(
                0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.assistantName,
    required this.onPick,
    required this.bottomPadding,
    required this.topPadding,
  });

  final String assistantName;
  final ValueChanged<String> onPick;
  final double bottomPadding;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color;
    final suggestions = <String>[
      'How does Scripture reveal Jesus in Genesis 1–3?',
      'What does John 1 teach about the Word?',
      'Explain Ephesians 2:8–10 in context.',
      'Where does the Bible say Jesus is the Son of God?',
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, bottomPadding + 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withOpacity(0.18),
                theme.colorScheme.secondary.withOpacity(0.12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withOpacity(0.2),
                ),
                alignment: Alignment.center,
                child: const AppLogo(size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Meet $assistantName',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bible theologian, grounded in Scripture and centered on Christ.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor?.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Try asking…',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in suggestions)
              ActionChip(label: Text(s), onPressed: () => onPick(s)),
          ],
        ),
      ],
    );
  }
}

class _ChatIntroBanner extends StatelessWidget {
  const _ChatIntroBanner({
    required this.assistantName,
    required this.onSavedChatsTap,
  });

  final String assistantName;
  final VoidCallback onSavedChatsTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final background = isDark
        ? const LinearGradient(
            colors: [Color(0xFF17171D), Color(0xFF20202B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFFF2ECFF), Color(0xFFECE9FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: background,
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 0.6,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 20),
              const SizedBox(width: 10),
              Text(
                assistantName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSavedChatsTap,
                child: const Text('Saved chats'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Ask Bible questions, trace themes to Jesus, and receive Scripture-rooted guidance.',
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.48,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(
                isDark ? 0.78 : 0.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BibleReferencePage extends StatelessWidget {
  const _BibleReferencePage({required this.reference});
  final ScriptureReference reference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(reference.display),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: BibleScreen(
        navVisible: false,
        initialBook: reference.book,
        initialChapter: reference.chapter,
        initialVerse: reference.verse,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
    );
  }
}

class _BlinkingLogo extends StatefulWidget {
  const _BlinkingLogo();

  @override
  State<_BlinkingLogo> createState() => _BlinkingLogoState();
}

class _BlinkingLogoState extends State<_BlinkingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: CustomPaint(
        size: const Size(16, 24),
        painter: _CrossPainter(color: Colors.white),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  _CrossPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final horizontalY =
        size.height * 0.35; // Position horizontal beam at 35% from top
    final horizontalWidth = size.width * 0.45; // Shorter horizontal beam

    // Vertical line (full height)
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), paint);

    // Horizontal line (shorter, positioned higher up)
    canvas.drawLine(
      Offset(centerX - horizontalWidth, horizontalY),
      Offset(centerX + horizontalWidth, horizontalY),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}
