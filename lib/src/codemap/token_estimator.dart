import 'dart:convert';
import 'package:codifyr/src/codemap/code_map_generator.dart';

/// Estimates the token count for a CodeMap object
///
/// This is useful for LLM context window planning
int estimateTokenCount(CodeMap codemap) {
  final jsonString = jsonEncode(codemap.toJson());
  final tokens = jsonString
      .split(RegExp(r'[\s{}[\],:"]+'))
      .where((token) => token.isNotEmpty)
      .length;
  return tokens;
}
