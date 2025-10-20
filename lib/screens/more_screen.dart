import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'default_page.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  Future<void> _handleLogout(BuildContext context) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AuthService().signOut();
        // AuthGate will automatically handle navigation back to login
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error logging out: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color containerColor = theme.colorScheme.surface.withOpacity(
      isDark ? 0.55 : 1.0,
    );
    final BorderRadius borderRadius = BorderRadius.circular(20);

    // Get current user info
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'Not signed in';
    final displayName = user?.displayName;

    return DefaultPage(
      title: 'More',
      emoji: '⋯',
      subtitle: 'Settings, downloads, and account live here.',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          _SectionHeader(
            title: 'Appearance',
            subtitle: 'Choose the theme that fits the moment.',
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: borderRadius,
            ),
            child: SwitchListTile.adaptive(
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            ),
          ),
          const SizedBox(height: 32),
          _SectionHeader(
            title: 'Library',
            subtitle: 'Keep Agape available even when you are offline.',
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: borderRadius,
            ),
            child: ListTile(
              leading: const Icon(Icons.cloud_download_rounded),
              title: const Text('Downloads'),
              subtitle: Text(
                'Manage offline chapters and audio.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor?.withOpacity(0.7),
                ),
              ),
              onTap: () {},
              shape: RoundedRectangleBorder(borderRadius: borderRadius),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: textColor?.withOpacity(0.4),
              ),
            ),
          ),
          const SizedBox(height: 32),
          _SectionHeader(
            title: 'Account',
            subtitle: displayName ?? userEmail,
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: borderRadius,
            ),
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      (displayName?.isNotEmpty == true
                          ? displayName![0].toUpperCase()
                          : userEmail[0].toUpperCase()),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(displayName ?? 'User'),
                  subtitle: Text(
                    userEmail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor?.withOpacity(0.7),
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: borderRadius.topLeft,
                      topRight: borderRadius.topRight,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text(
                    'Log Out',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => _handleLogout(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      bottomLeft: borderRadius.bottomLeft,
                      bottomRight: borderRadius.bottomRight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.textColor,
  });

  final String title;
  final String subtitle;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor?.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
