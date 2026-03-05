import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Manages conversation history (transcription sessions) using local SQLite.
class ConversationHistoryService {
  static final ConversationHistoryService _instance = ConversationHistoryService._internal();
  factory ConversationHistoryService() => _instance;
  ConversationHistoryService._internal();

  Database? _db;

  /// Initialize the SQLite database
  Future<void> initialize() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'hearwise_history.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            transcript TEXT NOT NULL,
            language TEXT DEFAULT 'auto',
            duration_seconds INTEGER DEFAULT 0,
            model_used TEXT DEFAULT 'tiny',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        debugPrint('✅ Conversation history database created');
      },
    );
  }

  /// Save a new conversation transcript
  Future<int> saveConversation({
    required String title,
    required String transcript,
    String language = 'auto',
    int durationSeconds = 0,
    String modelUsed = 'tiny',
  }) async {
    await initialize();
    final now = DateTime.now().toIso8601String();

    final id = await _db!.insert('conversations', {
      'title': title,
      'transcript': transcript,
      'language': language,
      'duration_seconds': durationSeconds,
      'model_used': modelUsed,
      'created_at': now,
      'updated_at': now,
    });

    debugPrint('💾 Saved conversation #$id: "$title"');
    return id;
  }

  /// Get all conversations, newest first
  Future<List<ConversationRecord>> getAllConversations() async {
    await initialize();
    final rows = await _db!.query(
      'conversations',
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => ConversationRecord.fromMap(r)).toList();
  }

  /// Get a single conversation by ID
  Future<ConversationRecord?> getConversation(int id) async {
    await initialize();
    final rows = await _db!.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return ConversationRecord.fromMap(rows.first);
  }

  /// Search conversations by keyword in title or transcript
  Future<List<ConversationRecord>> searchConversations(String query) async {
    await initialize();
    final rows = await _db!.query(
      'conversations',
      where: 'title LIKE ? OR transcript LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => ConversationRecord.fromMap(r)).toList();
  }

  /// Delete a conversation by ID
  Future<void> deleteConversation(int id) async {
    await initialize();
    await _db!.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint('🗑️ Deleted conversation #$id');
  }

  /// Delete all conversations
  Future<void> deleteAllConversations() async {
    await initialize();
    await _db!.delete('conversations');
    debugPrint('🗑️ Deleted all conversations');
  }

  /// Get total number of saved conversations
  Future<int> getConversationCount() async {
    await initialize();
    final result = await _db!.rawQuery('SELECT COUNT(*) as count FROM conversations');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Export a conversation as a text string
  String exportConversation(ConversationRecord record) {
    final buffer = StringBuffer();
    buffer.writeln('═' * 50);
    buffer.writeln('HearWise Conversation Transcript');
    buffer.writeln('═' * 50);
    buffer.writeln('Title: ${record.title}');
    buffer.writeln('Date: ${record.createdAt}');
    buffer.writeln('Language: ${record.language}');
    buffer.writeln('Duration: ${_formatDuration(record.durationSeconds)}');
    buffer.writeln('Model: ${record.modelUsed}');
    buffer.writeln('─' * 50);
    buffer.writeln(record.transcript);
    buffer.writeln('═' * 50);
    return buffer.toString();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  /// Dispose database connection
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}

/// Represents a single conversation record from the database
class ConversationRecord {
  final int id;
  final String title;
  final String transcript;
  final String language;
  final int durationSeconds;
  final String modelUsed;
  final String createdAt;
  final String updatedAt;

  ConversationRecord({
    required this.id,
    required this.title,
    required this.transcript,
    required this.language,
    required this.durationSeconds,
    required this.modelUsed,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationRecord.fromMap(Map<String, dynamic> map) {
    return ConversationRecord(
      id: map['id'] as int,
      title: map['title'] as String,
      transcript: map['transcript'] as String,
      language: (map['language'] as String?) ?? 'auto',
      durationSeconds: (map['duration_seconds'] as int?) ?? 0,
      modelUsed: (map['model_used'] as String?) ?? 'tiny',
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m}m ${s}s';
  }

  String get formattedDate {
    try {
      final date = DateTime.parse(createdAt);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return createdAt;
    }
  }
}
