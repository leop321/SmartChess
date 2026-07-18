import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class ChessSpeechService {
  AudioPlayer? _player;
  bool _isInitialized = false;

  ChessSpeechService();

  /// Lazily initializes the audio player.
  void _initPlayer() {
    if (_player == null) {
      try {
        _player = AudioPlayer();
        _isInitialized = true;
      } catch (e) {
        // In headless unit tests, AudioPlayer initialization can fail due to lack of binary messenger.
        _isInitialized = false;
        debugPrint('ChessSpeechService warning: Failed to initialize AudioPlayer: $e');
      }
    }
  }

  /// Plays a sequence of chess tokens back-to-back using a concatenating playlist.
  /// E.g. tokens = ['knight', 'takes', 'd', '4']
  Future<void> playMove(List<String> tokens) async {
    _initPlayer();
    if (!_isInitialized || _player == null) return;
    if (tokens.isEmpty) return;

    try {
      // 1. Stop any currently playing audio
      await _player!.stop();

      // 2. Build the playlist of assets
      final List<AudioSource> sources = [];
      for (final token in tokens) {
        // Sanitize token to ensure it contains only letters, numbers, or underscores
        final cleanToken = token.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
        if (cleanToken.isEmpty) continue;

        // Path to the asset sound
        final assetPath = 'assets/audio/$cleanToken.mp3';
        
        // Add asset source to the list
        sources.add(AudioSource.asset(assetPath));
      }

      if (sources.isEmpty) return;

      // 3. Load the sources into the player directly
      await _player!.setAudioSources(sources);

      // 5. Play the sequence
      // We don't await the play() completion here, so that the call returns immediately
      // and doesn't block the caller while speaking the sentence.
      _player!.play();
    } catch (e) {
      // Print warning (e.g. if files are not present in assets folder)
      debugPrint('ChessSpeechService warning: Failed to play move sequence. Error: $e');
      debugPrint('Please ensure all required audio files are present in the assets/audio/ directory.');
    }
  }

  /// Stops current playback.
  Future<void> stop() async {
    if (_player != null) {
      await _player!.stop();
    }
  }

  /// Disposes resources.
  void dispose() {
    _player?.dispose();
    _player = null;
    _isInitialized = false;
  }
}
