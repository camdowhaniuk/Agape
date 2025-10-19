import 'package:flutter/material.dart';

import 'default_page.dart';
import 'highlights_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color;

    return DefaultPage(
      title: 'More',
      emoji: '⋯',
      subtitle: 'Settings, downloads, and account live here.',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        children: [
          Column(
            children: [
              Text('⋯', style: theme.textTheme.displaySmall),
              const SizedBox(height: 12),
              Text('More', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Settings, downloads, and account live here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor?.withOpacity(0.72),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.brush_rounded),
            title: const Text('Highlights'),
            subtitle: Text(
              'Review and revisit highlighted passages.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor?.withOpacity(0.7),
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HighlightsScreen()),
              );
            },
          ),
          const Divider(height: 32),
          SwitchListTile.adaptive(
            value: isDarkMode,
            onChanged: onDarkModeChanged,
            title: const Text('Dark mode'),
            subtitle: Text(
              'Reduce eye strain with a darker theme.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor?.withOpacity(0.7),
              ),
            ),
            secondary: const Icon(Icons.brightness_2_rounded),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.cloud_download_rounded),
            title: const Text('Downloads'),
            subtitle: Text(
              'Manage offline chapters and audio.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor?.withOpacity(0.7),
              ),
            ),
            onTap: () {},
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('Account'),
            subtitle: Text(
              'Sign in to sync devices.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor?.withOpacity(0.7),
              ),
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
