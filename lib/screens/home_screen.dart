
import 'package:flutter/material.dart';
import 'default_page.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultPage(
      title: "Home",
      emoji: "🏠",
      subtitle: "This will be your dashboard with quick links, plans, and recent notes.",
    );
  }
}
