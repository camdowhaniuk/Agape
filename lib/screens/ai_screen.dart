import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../services/ai_conversation.dart';
import '../services/ai_conversation_store.dart';
import '../services/ai_service.dart';
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
  });

  final void Function(bool)? onScrollVisibilityChange;
  final bool navVisible;
  final int activationTick;
  final int navVisibilityResetTick;

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  static const String _assistantName = 'Agape';
  static const double _navOverlayHeight = 58;

  static const String _systemPrompt =
      'You are the absolute best Bible theologian-teacher. Interpret Scripture with humility, '
      'historic orthodox faith, and a Christ-centered lens (Luke 24:27). '
      'Treat the Bible as the Word of God revealing Jesus the Son of God. '
      'Prefer Scripture to speculation. Cite passages naturally. Be pastoral, clear, and concise while also remaining friendly.'
      'Reflect the character of Jesus in your words. Full of grace and truth. '
      'Your name is Agape to bring reverance to the love of Jesus Christ that surpasses all knowledge. '
      'Reflect the wisdom of Jesus in your answers. ';

  late final AIService _service = AIService(systemPrompt: _systemPrompt);
  final AIConversationStore _store = AIConversationStore();
  final List<AIMessage> _messages = [];
  List<AIConversation> _conversations = const <AIConversation>[];
  String? _activeConversationId;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  bool _sending = false;
  bool _chromeVisible = true;
  bool _navVisibilityArmed = false;
  bool _navVisibilityPrimed = false;
  double? _lastScrollOffset;
  bool _pendingEnsureBottom = false;
  int _ensureBottomAttempts = 0;
  final GlobalKey _bottomAnchorKey = GlobalKey();
  double? _lastObservedMaxExtent;
  bool _navRevealSuppressed = false;
  bool _composerFocused = false;

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
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final conversations = await _store.loadAll();
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
      return;
    }
    final active = _resolveActive(
      conversations,
      preferId: _activeConversationId,
    );
    setState(() {
      _conversations = conversations;
      _activeConversationId = active?.id;
      _messages
        ..clear()
        ..addAll(active?.messages ?? const <AIMessage>[]);
    });
    if (_messages.isNotEmpty) {
      _jumpToBottomSoon();
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
    final userMessage = AIMessage(role: AIRole.user, content: text);
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _controller.clear();
    });
    _jumpToBottomSoon();
    await _persistActiveConversation();

    try {
      final reply = await _service.reply(history: _messages, userMessage: text);
      if (!mounted) return;
      final assistantMessage = AIMessage(
        role: AIRole.assistant,
        content: reply,
      );
      setState(() {
        _messages.add(assistantMessage);
      });
      await _persistActiveConversation();
      _requestEnsureBottom();
    } catch (error) {
      if (!mounted) return;
      debugPrint('AI reply failed: $error');
      final bool authError = error is AIServiceAuthException;
      final fallback = AIMessage(
        role: AIRole.assistant,
        content: authError
            ? 'I need your OpenAI API key before I can respond. Launch the app with '
                  '--dart-define=OPENAI_API_KEY=your_key and try again.'
            : 'I ran into a problem replying just now. Would you try again? (Error: $error)',
      );
      setState(() {
        _messages.add(fallback);
      });
      await _persistActiveConversation();
    } finally {
      if (mounted) setState(() => _sending = false);
      _jumpToBottomSoon();
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
    _requestEnsureBottom();
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
    if (_messages.isEmpty) return;
    _requestEnsureBottom();
  }

  void _requestEnsureBottom() {
    if (_messages.isEmpty) {
      _pendingEnsureBottom = false;
      return;
    }
    if (_pendingEnsureBottom) return;
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
    final context = _bottomAnchorKey.currentContext;
    if (context == null || !_scroll.hasClients) {
      if (_ensureBottomAttempts++ < 30) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureBottomVisible(),
        );
      } else {
        _pendingEnsureBottom = false;
      }
      return;
    }
    final position = _scroll.position;
    final previousMax = _lastObservedMaxExtent;
    final currentMax = position.maxScrollExtent;
    if (currentMax <= 0) {
      if (_ensureBottomAttempts++ < 30) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureBottomVisible(),
        );
      } else {
        _pendingEnsureBottom = false;
      }
      return;
    }
    if (previousMax == null || (currentMax - previousMax).abs() > 1.0) {
      _lastObservedMaxExtent = currentMax;
      if (_ensureBottomAttempts++ < 30) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ensureBottomVisible(),
        );
      } else {
        _pendingEnsureBottom = false;
      }
      return;
    }
    _pendingEnsureBottom = false;
    _lastObservedMaxExtent = null;
    _ensureBottomAttempts = 0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final navPadding = widget.navVisible ? _navOverlayHeight : 0;
    final extra = bottomPadding + navPadding + 8;
    position.jumpTo((currentMax + extra).clamp(0.0, currentMax + extra));
  }

  Future<void> _refreshConversations({String? preferId}) async {
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
    if (_messages.isNotEmpty) {
      _jumpToBottomSoon();
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
    if (_chromeVisible == visible) {
      if (force && visible) {
        _resetNavVisibilityArming();
      }
      return;
    }
    setState(() => _chromeVisible = visible);
    if (force && visible) {
      _resetNavVisibilityArming();
    }
    widget.onScrollVisibilityChange?.call(visible);
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
    final double keyboardInset = media.viewInsets.bottom;
    final double navPadding = widget.navVisible ? _navOverlayHeight : 0;
    final double navAwarePadding = navPadding + bottomInset;
    const double floatingComposerHeight = 58;
    final bool showComposer =
        _composerFocused || _chromeVisible || keyboardInset > 0;
    final double composerBottomInset = keyboardInset > 0
        ? keyboardInset + 8
        : (widget.navVisible ? navAwarePadding + 4 : bottomInset + 8);
    final double listBottomPadding;
    if (keyboardInset > 0) {
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
        media.padding.top + (_chromeVisible ? 86 : 48);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildChatBody(
              bottomPadding: listBottomPadding,
              topPadding: listTopPadding,
            ),
          ),
          AnimatedPositioned(
            left: 16,
            right: 16,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            bottom: showComposer
                ? composerBottomInset
                : -(floatingComposerHeight + 24),
            child: IgnorePointer(
              ignoring: !showComposer && keyboardInset <= 0,
              child: AnimatedOpacity(
                opacity: showComposer ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
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
          AnimatedPositioned(
            left: 16,
            right: 16,
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
                    FloatingActionButton(
                      heroTag: 'agape-new-chat',
                      onPressed: _newChat,
                      child: const Icon(Icons.add_comment_rounded),
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

    final bool showTypingBubble = _sending;
    final bool includeIntro = true;
    final int messageStartIndex = includeIntro ? 1 : 0;
    final int typingOffset = showTypingBubble ? 1 : 0;
    final int totalCount = _messages.length + messageStartIndex + typingOffset;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
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

          if (_sending && index == totalCount - 1) {
            return const _TypingBubble();
          }

          final messageIndex = index - messageStartIndex;
          final m = _messages[messageIndex];
          return _ChatBubble(
            content: m.content,
            fromUser: m.role == AIRole.user,
            timestamp: m.timestamp,
            assistantName: _assistantName,
          );
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
    final Color bgColor = widget.isDark
        ? const Color(0xFF242429).withOpacity(0.9)
        : scheme.surface.withOpacity(0.96);
    final Color borderColor = widget.isDark
        ? Colors.white10
        : Colors.black12.withOpacity(0.12);
    final Color buttonColor = scheme.primary;

    return Material(
      color: Colors.transparent,
      elevation: widget.isDark ? 10 : 14,
      shadowColor: Colors.black.withOpacity(widget.isDark ? 0.5 : 0.2),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 0.7),
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
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.55),
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
    );
  }
}

class _SurfaceIconButton extends StatelessWidget {
  const _SurfaceIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color base = isDark
        ? const Color(0xFF242429).withOpacity(0.9)
        : theme.colorScheme.surface.withOpacity(0.96);
    final BorderRadius radius = BorderRadius.circular(20);

    return Material(
      color: base,
      elevation: isDark ? 6 : 8,
      borderRadius: radius,
      shadowColor: Colors.black.withOpacity(isDark ? 0.45 : 0.18),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 22,
        color: theme.colorScheme.onSurface,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.content,
    required this.fromUser,
    required this.timestamp,
    required this.assistantName,
  });

  final String content;
  final bool fromUser;
  final DateTime timestamp;
  final String assistantName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = fromUser
        ? (isDark ? const Color(0xFF2B2B30) : Colors.white)
        : (isDark ? const Color(0xFF1F1F23) : const Color(0xFFF1ECF8));
    final fg = fromUser
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? Colors.white.withOpacity(0.92) : Colors.black87);
    final align = fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(fromUser ? 16 : 4),
      bottomRight: Radius.circular(fromUser ? 4 : 16),
    );
    final meta = TimeOfDay.fromDateTime(timestamp).format(context);

    void openReference(ScriptureReference ref) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _BibleReferencePage(reference: ref)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 640),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!fromUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF7954B1),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          assistantName,
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.2,
                            fontWeight: FontWeight.w600,
                            color: fg.withOpacity(isDark ? 0.9 : 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                MarkdownMessage(
                  markdown: content,
                  baseStyle: TextStyle(height: 1.48, fontSize: 16, color: fg),
                  isDark: isDark,
                  linkColor: theme.colorScheme.primary,
                  onScriptureTap: openReference,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bubbleColor = isDark
        ? const Color(0xFF242429).withOpacity(0.88)
        : Colors.white.withOpacity(0.96);
    final Color borderColor = isDark
        ? Colors.white12
        : Colors.black12.withOpacity(0.16);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
            border: Border.all(color: borderColor, width: 0.6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 46,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    3,
                    (i) => _Dot(delay: Duration(milliseconds: 200 * i)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delay});
  final Duration delay;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = ((_c.value + widget.delay.inMilliseconds / 900) % 1.0);
        final up = t < 0.5 ? (t / 0.5) : (1 - (t - 0.5) / 0.5);
        final dy = 2.0 * up;
        return Transform.translate(offset: Offset(0, -dy), child: child);
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : Colors.black54,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
