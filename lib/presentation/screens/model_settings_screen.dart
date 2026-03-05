import 'package:flutter/material.dart';
import '../../data/services/model_manager_service.dart';

class ModelSettingsScreen extends StatefulWidget {
  const ModelSettingsScreen({super.key});

  @override
  State<ModelSettingsScreen> createState() => _ModelSettingsScreenState();
}

class _ModelSettingsScreenState extends State<ModelSettingsScreen> {
  final ModelManagerService _modelManager = ModelManagerService();
  List<Map<String, dynamic>> _models = [];
  String _activeModel = 'tiny';
  bool _isLoading = true;
  String? _downloadingModel;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadModelInfo();
  }

  Future<void> _loadModelInfo() async {
    setState(() => _isLoading = true);
    _models = await _modelManager.getDownloadedModels();
    _activeModel = await _modelManager.getActiveWhisperModel();
    setState(() => _isLoading = false);
  }

  Future<void> _downloadModel(String name) async {
    setState(() {
      _downloadingModel = name;
      _downloadProgress = 0;
    });

    try {
      await _modelManager.downloadModel(
        name,
        onProgress: (progress) {
          setState(() => _downloadProgress = progress);
        },
      );
      _showSnackBar('Model "$name" downloaded successfully ✓', const Color(0xFF4CAF50));
    } catch (e) {
      _showSnackBar('Download failed: $e', Colors.red);
    }

    setState(() => _downloadingModel = null);
    _loadModelInfo();
  }

  Future<void> _deleteModel(String name) async {
    if (name == 'tiny') {
      _showSnackBar('Cannot delete the default model', Colors.orange);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2139),
        title: const Text('Delete Model', style: TextStyle(color: Colors.white)),
        content: Text('Delete Whisper "$name"? You can re-download it later.',
            style: const TextStyle(color: Colors.white70)),
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
      await _modelManager.deleteModel(name);
      _loadModelInfo();
    }
  }

  Future<void> _setActiveModel(String name) async {
    await _modelManager.setActiveWhisperModel(name);
    setState(() => _activeModel = name);
    _showSnackBar('Active model set to "$name"', const Color(0xFF6C63FF));
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.model_training, color: Color(0xFF6C63FF), size: 24),
            const SizedBox(width: 12),
            const Text("AI Models", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Info card ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF6C63FF), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Larger models give better accuracy for Urdu & Punjabi but use more storage. The tiny model is always available.',
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8), height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Section: Transcription Models ──
                  Text("Whisper Transcription Models",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9))),
                  const SizedBox(height: 12),

                  ...(_models.map((model) => _buildModelCard(model))),

                  const SizedBox(height: 24),

                  // ── Section: Audio Processing Models ──
                  Text("Audio Processing Models",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9))),
                  const SizedBox(height: 12),

                  _buildFixedModelCard(
                    'RNNoise',
                    'Noise Suppression',
                    '~1 MB',
                    'Removes background noise while preserving speech. Language-agnostic.',
                    Icons.noise_aware,
                  ),
                  const SizedBox(height: 12),
                  _buildFixedModelCard(
                    'DTLN',
                    'Voice Isolation',
                    '~4 MB',
                    'Isolates human voice from all background sounds. Dual-stage LSTM network.',
                    Icons.record_voice_over,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildModelCard(Map<String, dynamic> model) {
    final name = model['name'] as String;
    final downloaded = model['downloaded'] as bool;
    final size = model['size'] as int;
    final urdu = model['urdu'] as String;
    final english = model['english'] as String;
    final isActive = name == _activeModel;
    final isDownloading = _downloadingModel == name;
    final isTiny = name == 'tiny';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFF6C63FF).withOpacity(0.5) : Colors.white.withOpacity(0.1),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Text('Whisper ${name.toUpperCase()}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('ACTIVE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                ),
              if (isTiny && !isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('BUNDLED',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.6))),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Language accuracy row
          Row(
            children: [
              _langBadge('English', english),
              const SizedBox(width: 8),
              _langBadge('Urdu', urdu),
              const Spacer(),
              Text('${size} MB', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
            ],
          ),

          const SizedBox(height: 12),

          // Download progress
          if (isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF6C63FF)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text('Downloading... ${(_downloadProgress * 100).toInt()}%',
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
          ],

          // Action buttons
          if (!isDownloading)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!downloaded && !isTiny)
                  _actionButton('Download', Icons.download, const Color(0xFF6C63FF), () => _downloadModel(name)),
                if (downloaded && !isActive)
                  _actionButton('Set Active', Icons.check_circle_outline, const Color(0xFF4CAF50), () => _setActiveModel(name)),
                if (downloaded && !isTiny) ...[
                  const SizedBox(width: 8),
                  _actionButton('Delete', Icons.delete_outline, const Color(0xFFE91E63), () => _deleteModel(name)),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _langBadge(String lang, String quality) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$lang: $quality', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedModelCard(String name, String subtitle, String size, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF4CAF50), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('BUNDLED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), height: 1.3)),
              ],
            ),
          ),
          Text(size, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
        ],
      ),
    );
  }
}
