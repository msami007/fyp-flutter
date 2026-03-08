import 'package:flutter/material.dart';
import '../../data/services/conversation_history_service.dart';

class ConversationHistoryScreen extends StatefulWidget {
  const ConversationHistoryScreen({super.key});

  @override
  State<ConversationHistoryScreen> createState() => _ConversationHistoryScreenState();
}

class _ConversationHistoryScreenState extends State<ConversationHistoryScreen> {
  final ConversationHistoryService _historyService = ConversationHistoryService();
  List<ConversationRecord> _conversations = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    final conversations = _searchQuery.isEmpty
        ? await _historyService.getAllConversations()
        : await _historyService.searchConversations(_searchQuery);
    setState(() {
      _conversations = conversations;
      _isLoading = false;
    });
  }

  Future<void> _deleteConversation(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2139),
        title: const Text('Delete Transcript', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFE91E63))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyService.deleteConversation(id);
      _loadConversations();
    }
  }

  void _viewConversation(ConversationRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2139),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title & Meta
              Text(record.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _metaChip(Icons.calendar_today, record.formattedDate),
                  const SizedBox(width: 8),
                  _metaChip(Icons.timer, record.formattedDuration),
                  const SizedBox(width: 8),
                  _metaChip(Icons.language, record.language.toUpperCase()),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 8),

              // Transcript
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(
                    record.transcript,
                    style: const TextStyle(fontSize: 16, color: Colors.white, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF6C63FF), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Conversation History",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Search bar
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E2139),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search transcripts...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF6C63FF)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (val) {
                  _searchQuery = val;
                  _loadConversations();
                },
              ),
            ),

            const SizedBox(height: 16),

            // Conversation list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
                  : _conversations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 48, color: Colors.white.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty ? 'No saved transcripts yet' : 'No results found',
                                style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.5)),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final conv = _conversations[index];
                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2139),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                title: Text(conv.title,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      conv.transcript.length > 80
                                          ? '${conv.transcript.substring(0, 80)}...'
                                          : conv.transcript,
                                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _metaChip(Icons.calendar_today, conv.formattedDate),
                                        const SizedBox(width: 6),
                                        _metaChip(Icons.timer, conv.formattedDuration),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFE91E63), size: 20),
                                  onPressed: () => _deleteConversation(conv.id),
                                ),
                                onTap: () => _viewConversation(conv),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
