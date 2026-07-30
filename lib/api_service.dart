import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PredictionResult {
  final String? word;
  final double confidence;
  final bool hasConfidence;
  final String? message;
  final String raw;

  const PredictionResult(
    this.word,
    this.confidence,
    this.raw, {
    this.hasConfidence = false,
    this.message,
  });
}

class ApiService {
  static const String baseUrl = 'https://muaaz11-asl-backend.hf.space';
  static const String endpoint = '/predict';

  // Reusing one client keeps the HTTPS connection alive between captures.
  // This avoids repeating part of the connection setup on every prediction.
  static final http.Client _client = http.Client();

  static Future<void> warmUp() async {
    try {
      await _client
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 10));
      debugPrint('Alphabet backend warmed up');
    } catch (_) {
      debugPrint('Alphabet backend warm-up failed');
    }
  }

  static Future<PredictionResult?> predictClip(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl$endpoint'),
      );
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamed);

      debugPrint('Alphabet API status: ${response.statusCode}');
      debugPrint('Alphabet API response: ${response.body}');

      if (response.statusCode != 200) {
        return PredictionResult(
          null,
          0.0,
          response.body,
          message: 'Server error (${response.statusCode})',
        );
      }

      final dynamic data = jsonDecode(response.body);
      return _parse(data, response.body);
    } on TimeoutException {
      debugPrint('Alphabet API timeout');
      return const PredictionResult(
        null,
        0.0,
        'Timeout',
        message: 'Server timeout — retrying',
      );
    } catch (e) {
      debugPrint('Alphabet API error: $e');
      return PredictionResult(
        null,
        0.0,
        'ERROR: $e',
        message: 'Connection error — retrying',
      );
    }
  }

  static PredictionResult _parse(dynamic data, String raw) {
    if (data is String) {
      return PredictionResult(
        _cleanLabel(data),
        0.0,
        raw,
        hasConfidence: false,
      );
    }

    if (data is List) {
      if (data.isEmpty) return PredictionResult(null, 0.0, raw);
      return _parse(data.first, raw);
    }

    if (data is Map) {
      // Some APIs wrap the real response inside data/output/result.
      for (final wrapper in ['data', 'output']) {
        final nested = data[wrapper];
        if (nested is Map || nested is List) {
          final parsed = _parse(nested, raw);
          if (parsed.word != null || parsed.message != null) return parsed;
        }
      }

      String? word;
      for (final key in [
        'prediction',
        'word',
        'label',
        'sign',
        'class',
        'result',
        'gloss',
        'text',
      ]) {
        final value = data[key];
        if (value != null && value is! Map && value is! List) {
          word = _cleanLabel(value.toString());
          if (word != null) break;
        }
      }

      double confidence = 0.0;
      bool hasConfidence = false;
      for (final key in [
        'confidence',
        'score',
        'probability',
        'prob',
        'accuracy',
      ]) {
        final value = data[key];
        final parsed = value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '');
        if (parsed != null) {
          confidence = parsed > 1.0 && parsed <= 100.0
              ? parsed / 100.0
              : parsed;
          confidence = confidence.clamp(0.0, 1.0).toDouble();
          hasConfidence = true;
          break;
        }
      }

      final String? message =
          data['message']?.toString() ?? data['error']?.toString();

      return PredictionResult(
        word,
        confidence,
        raw,
        hasConfidence: hasConfidence,
        message: message,
      );
    }

    return PredictionResult(null, 0.0, raw);
  }

  static String? _cleanLabel(String value) {
    var label = value.trim().toUpperCase();
    if (label.isEmpty || label == 'NULL' || label == 'NONE') return null;

    // Alphabet mode must only append one A-Z character. This prevents an
    // unexpected server message such as "no hand" from entering the word.
    final match = RegExp(r'^[A-Z]$').firstMatch(label);
    return match?.group(0);
  }
}
