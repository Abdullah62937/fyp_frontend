import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String _encodeSequencePayload(List<List<double>> sequence) {
  final compactSequence = sequence
      .map(
        (frame) => frame
            .map((value) => value.isFinite
                ? (value * 100000).round() / 100000
                : 0.0)
            .toList(growable: false),
      )
      .toList(growable: false);
  return jsonEncode({'sequence': compactSequence});
}

class WordPredictionResult {
  final String? prediction;
  final double confidence;
  final double bufferFill;
  final bool ready;
  final String? error;

  const WordPredictionResult({
    this.prediction,
    this.confidence = 0.0,
    this.bufferFill = 0.0,
    this.ready = false,
    this.error,
  });

  factory WordPredictionResult.fromJson(Map<String, dynamic> json) {
    return WordPredictionResult(
      prediction: _cleanPrediction(json['prediction']),
      confidence: _normaliseConfidence(json['confidence']),
      bufferFill: _normaliseConfidence(json['buffer_fill']),
      ready: json['ready'] as bool? ?? false,
      error: json['error']?.toString(),
    );
  }

  static String? _cleanPrediction(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'none') return null;
    return text;
  }

  static double _normaliseConfidence(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) return 0.0;
    final normalised = parsed > 1.0 && parsed <= 100.0
        ? parsed / 100.0
        : parsed;
    return normalised.clamp(0.0, 1.0).toDouble();
  }
}

class WordApiService {
  static const String baseUrl = 'https://fypwasl-production.up.railway.app';
  static const String predictFrameEndpoint = '/predict_frame';
  static const String predictSequenceEndpoint = '/predict_sequence';
  static const String resetEndpoint = '/reset';

  static final http.Client _client = http.Client();

  static Future<void> warmUp() async {
    try {
      await _client
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 10));
      debugPrint('Word backend warmed up');
    } catch (_) {
      debugPrint('Word backend warm-up failed');
    }
  }

  static Future<void> reset() async {
    try {
      await _client
          .post(Uri.parse('$baseUrl$resetEndpoint'))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Word reset error: $e');
    }
  }

  static Future<WordPredictionResult?> predictSequence(
    List<List<double>> sequence,
  ) async {
    if (sequence.length != 30 ||
        sequence.any((frame) => frame.length != 258)) {
      return const WordPredictionResult(
        error: 'Invalid motion sequence — please retry',
      );
    }

    try {
      // Encoding ~7,700 landmark values can briefly block the camera/UI in
      // debug mode. Build the compact JSON payload on a background isolate.
      final body = await compute(_encodeSequencePayload, sequence);

      final response = await _client
          .post(
            Uri.parse('$baseUrl$predictSequenceEndpoint'),
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return WordPredictionResult(
          error: 'Server error (${response.statusCode}) — retrying',
        );
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const WordPredictionResult(error: 'Invalid server response');
      }
      final data = Map<String, dynamic>.from(decoded);
      return WordPredictionResult(
        prediction: WordPredictionResult._cleanPrediction(data['prediction']),
        confidence:
            WordPredictionResult._normaliseConfidence(data['confidence']),
        bufferFill: 1.0,
        ready: true,
        error: data['error']?.toString(),
      );
    } on TimeoutException {
      return const WordPredictionResult(
        error: 'Server timeout — keep camera steady and retry',
      );
    } catch (e) {
      debugPrint('Word sequence error: $e');
      return const WordPredictionResult(error: 'Connection error — retrying');
    }
  }

  static Future<WordPredictionResult?> predictFrame(
    List<double> keypoints,
  ) async {
    if (keypoints.length != 258) {
      return const WordPredictionResult(error: 'Invalid keypoint frame');
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl$predictFrameEndpoint'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'keypoints': keypoints}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return WordPredictionResult(
          error: 'Server error (${response.statusCode})',
        );
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const WordPredictionResult(error: 'Invalid server response');
      }
      return WordPredictionResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on TimeoutException {
      return const WordPredictionResult(error: 'Server timeout');
    } catch (e) {
      debugPrint('Word frame error: $e');
      return const WordPredictionResult(error: 'Connection error');
    }
  }
}
