import 'package:flutter/material.dart';
import '../models/app_state.dart';

class SidebarDrawer extends StatelessWidget {
  final AppState appState;

  const SidebarDrawer({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF6366F1); // Indigo Primary
    final inactiveColor = const Color(0xFF94A3B8); // Slate Secondary
    final cardBg = const Color(0xFF151E2E); // Surface Card
    final border = const Color(0xFF1E293B); // Border

    return Drawer(
      backgroundColor: const Color(0xFF0B0F19), // Dark App Bg
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Logo icon with gradient
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withAlpha(51),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.psychology,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Local AI',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'v1.0.0 (Local Engine)',
                            style: TextStyle(
                              fontSize: 11,
                              color: inactiveColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Offline Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'OFFLINE-FIRST',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(color: Color(0xFF1E293B), height: 1),

            // Navigation List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                children: [
                  _buildNavItem(
                    context: context,
                    icon: Icons.chat_bubble_outline,
                    title: 'Chat Assistant',
                    active: appState.activeScreen == AppScreen.chat,
                    onTap: () {
                      Navigator.pop(context);
                      appState.switchScreen(AppScreen.chat);
                    },
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                  ),
                  const SizedBox(height: 8),
                  _buildNavItem(
                    context: context,
                    icon: Icons.history,
                    title: 'History',
                    active: appState.activeScreen == AppScreen.history,
                    onTap: () {
                      Navigator.pop(context);
                      appState.switchScreen(AppScreen.history);
                    },
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                  ),
                  const SizedBox(height: 8),
                  _buildNavItem(
                    context: context,
                    icon: Icons.memory,
                    title: 'Local Models',
                    active: appState.activeScreen == AppScreen.models,
                    onTap: () {
                      Navigator.pop(context);
                      appState.switchScreen(AppScreen.models);
                    },
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                  ),
                ],
              ),
            ),

            // Drawer Footer (Storage details)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Device Storage',
                          style: TextStyle(
                            fontSize: 11,
                            color: inactiveColor,
                          ),
                        ),
                        const Text(
                          '14.2 GB Free',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Storage Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 0.55,
                        backgroundColor: border,
                        valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'System RAM footprint is managed dynamically.',
                      style: TextStyle(
                        fontSize: 9,
                        color: inactiveColor.withAlpha(178),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool active,
    required VoidCallback onTap,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: active ? activeColor.withAlpha(25) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        leading: Icon(
          icon,
          color: active ? activeColor : inactiveColor,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? activeColor : Colors.white70,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
        dense: true,
      ),
    );
  }
}
