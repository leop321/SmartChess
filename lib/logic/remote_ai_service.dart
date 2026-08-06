import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../model/api_models.dart';

// ---------------------------------------------------------------------------
// Custom Exceptions
// ---------------------------------------------------------------------------

abstract class RemoteAiException implements Exception {
  final String message;
  RemoteAiException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class ApiTimeoutException extends RemoteAiException {
  ApiTimeoutException(super.message);
}

class InvalidFenException extends RemoteAiException {
  InvalidFenException(super.message);
}

class EngineErrorException extends RemoteAiException {
  EngineErrorException(super.message);
}

// ---------------------------------------------------------------------------
// Service Implementation
// ---------------------------------------------------------------------------

class RemoteAiService {
  final String baseUrl;
  final http.Client _client;

  RemoteAiService({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Requests the best move from the Python FastAPI backend.
  /// Throws [RemoteAiException] or its subclasses on errors.
  Future<MoveResponse> getBotMove(MoveRequest request) async {
    final uri = Uri.parse('$baseUrl/api/v1/move');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MoveResponse.fromJson(data);
      } else if (response.statusCode == 400) {
        // Custom 400 cases (e.g. unknown bot ID)
        throw EngineErrorException('Bad Request: ${response.body}');
      } else if (response.statusCode == 422) {
        // FastAPI / Pydantic validation errors
        throw InvalidFenException(
            'Unprocessable Entity (Invalid FEN or Format): ${response.body}');
      } else if (response.statusCode == 500) {
        // Internal server errors (Engine timeout, crash, etc)
        throw EngineErrorException('Internal Server Error: ${response.body}');
      } else {
        // Any other HTTP error
        throw EngineErrorException(
            'Unexpected HTTP Status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (e is RemoteAiException) {
        // Re-throw our custom exceptions
        rethrow;
      } else {
        // Wrap network connection / timeout errors
        throw ApiTimeoutException(
            'Connection to AI Backend failed or timed out: $e');
      }
    }
  }

  /// Offloads board evaluation/analysis to the backend.
  Future<AnalysisResponse> analyzeFen(String fen, {int depth = 14}) async {
    final uri = Uri.parse('$baseUrl/api/v1/analyze');
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'fen': fen,
              'depth': depth,
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return AnalysisResponse.fromJson(data);
      } else {
        throw EngineErrorException(
            'Server returned status ${response.statusCode}');
      }
    } catch (e) {
      if (e is RemoteAiException) {
        rethrow;
      } else {
        throw ApiTimeoutException('Analysis request failed: $e');
      }
    }
  }

  /// Sends a lightweight GET request to the /health endpoint.

  /// Used for warming up the server during cold starts on Render.com free tier.
  Future<bool> pingServer() async {
    final uri = Uri.parse('$baseUrl/health');
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Riverpod Provider
// ---------------------------------------------------------------------------

/// Detects the correct backend URL at runtime.
/// - Android Emulator: 10.0.2.2 (loopback to host machine)
/// - iOS Simulator:    localhost
/// - Real device:      requires the HOST machine's local network IP.
///   Set the env variable AI_BACKEND_URL or the const below to override.
String _resolveBackendUrl() {
  // Check for an override first (useful for CI / real-device testing).
  // ignore: do_not_use_environment
  const override = String.fromEnvironment('AI_BACKEND_URL', defaultValue: '');
  if (override.isNotEmpty) return override;

  if (kIsWeb) {
    return 'http://localhost:8000';
  }

  // Standard loopback mappings per platform.
  if (Platform.isAndroid) {
    // 10.0.2.2 only works in the Android Emulator.
    // On a real device, replace with your host machine's local LAN IP:
    // e.g. 'http://192.168.1.42:8000'
    return 'http://10.0.2.2:8000';
  }
  return 'http://localhost:8000';
}

/// Provider for the Remote AI Service.
final remoteAiServiceProvider = Provider<RemoteAiService>((ref) {
  return RemoteAiService(baseUrl: _resolveBackendUrl());
});
