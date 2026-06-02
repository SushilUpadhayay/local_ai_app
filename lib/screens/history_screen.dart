import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../models/conversation.dart';

class HistoryScreen extends StatefulWidget {
  final AppState appState;

  const HistoryScreen({super.key, required this.appState});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.appState.historySearchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = widget.appState.getFilteredConversations();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF151E2E), // Card Surface
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.search, color: Color(0xFF94A3B8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search conversations...',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (val) {
                      widget.appState.searchHistory(val);
                    },
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      widget.appState.searchHistory('');
                    },
                    child: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 16),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Title Header
          const Text(
            'RECENT CONVERSATIONS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),

          // Scrollable List of cards
          Expanded(
            child: conversations.isEmpty
                ? const Center(
                    child: Text(
                      'No conversations found',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildHistoryCard(conv),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Conversation conv) {
    return GestureDetector(
      onTap: () {
        widget.appState.selectConversation(conv);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF151E2E), // Card Surface
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    conv.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  conv.timeLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              conv.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
