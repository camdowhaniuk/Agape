import 'package:flutter/material.dart';

import '../services/highlight_service.dart';
import '../utils/highlight_colors.dart';

class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({super.key});

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  final HighlightService _service = HighlightService();
  late Future<List<HighlightEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHighlights();
  }

  Future<List<HighlightEntry>> _loadHighlights() async {
    return _service.allHighlights();
  }

  Future<void> _refresh() async {
    final entries = await _loadHighlights();
    if (!mounted) return;
    setState(() {
      _future = Future.value(entries);
    });
  }

  Future<void> _deleteHighlight(HighlightEntry entry) async {
    final confirm = await _confirmDelete(entry);
    if (confirm != true) return;
    await _service.removeHighlightEntry(entry);
    await _refresh();
  }

  Future<bool?> _confirmDelete(HighlightEntry entry) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove highlight?'),
          content: Text('Delete the highlight for ${entry.reference}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Highlights')),
      body: FutureBuilder<List<HighlightEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load highlights.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }

          final entries = snapshot.data ?? const <HighlightEntry>[];
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Highlights you add will appear here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _HighlightTile(
                  entry: entry,
                  onDelete: () => _deleteHighlight(entry),
                  onTap: () => Navigator.of(context).pop(entry),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.entry,
    required this.onDelete,
    this.onTap,
  });

  final HighlightEntry entry;
  final Future<void> Function() onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = highlightColorForPassageHighlight(
      entry.highlight,
      dark: isDark,
    );
    final textColor = theme.textTheme.bodyMedium?.color;
    final excerpt = entry.highlight.excerpt?.trim().isNotEmpty == true
        ? entry.highlight.excerpt!
        : 'Highlight';

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 56,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.reference,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          excerpt,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor?.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete highlight',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => onDelete(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
