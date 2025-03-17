import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:yaml/yaml.dart';

class CodeMap {
  CodeMap({
    required this.project,
    required this.modules,
    required this.relationships,
    required this.dependencies,
  });

  final String project;
  final List<Module> modules;
  final Map<String, List<String>> relationships;
  final List<String> dependencies;

  Map<String, dynamic> toJson() => {
        'project': project,
        'modules': modules.map((m) => m.toJson()).toList(),
        'relationships': relationships,
        'dependencies': dependencies,
      };
}

class Module {
  Module({
    required this.name,
    required this.classes,
    required this.constructors,
    required this.functions,
    required this.dependencies,
  });

  final String name;
  final List<CodeElement> classes;
  final List<CodeElement> constructors;
  final List<CodeElement> functions;
  final List<String> dependencies;

  Map<String, dynamic> toJson() => {
        'name': name,
        'classes': classes.map((c) => c.toJson()).toList(),
        'constructors': constructors.map((c) => c.toJson()).toList(),
        'functions': functions.map((f) => f.toJson()).toList(),
        'dependencies': dependencies,
      };
}

class CodeElement extends Equatable {
  const CodeElement({
    required this.name,
    required this.signature,
  });

  final String name;
  final String signature;

  Map<String, dynamic> toJson() => {'name': name, 'signature': signature};

  @override
  List<Object?> get props => [name, signature];
}

class CodeMapGenerator {
  CodeMapGenerator({
    required this.projectPath,
    required this.outputJsonPath,
    this.configPath = 'codifyr.yaml',
  });

  final String projectPath;
  final String outputJsonPath;
  final String configPath;

  Future<CodeMap> generateCodeMap() async {
    if (!Directory('$projectPath/lib').existsSync() ||
        !File('$projectPath/pubspec.yaml').existsSync()) {
      throw Exception(
        'Not a valid Dart project. Missing pubspec.yaml or lib directory',
      );
    }

    final config = await _loadConfig();
    final codeMap = await _buildCodeMap(config);

    final outputFile = File(outputJsonPath);
    await outputFile.writeAsString(jsonEncode(codeMap.toJson()));
    return codeMap;
  }

  Future<Map<String, dynamic>> _loadConfig() async {
    final configFile = File('$projectPath/$configPath');
    if (!configFile.existsSync()) return {};

    final yamlMap = loadYaml(await configFile.readAsString()) as YamlMap;
    return yamlMap.nodes.keys.fold<Map<String, dynamic>>({}, (config, key) {
      final value = yamlMap.nodes[key];
      if (value is YamlList) {
        config[key.toString()] =
            value.nodes.map((node) => node.toString()).toList();
      } else {
        config[key.toString()] = value.toString();
      }
      return config;
    });
  }

  Future<List<String>> _getDirectDependencies() async {
    final pubspec = File('$projectPath/pubspec.yaml');
    final yamlContent = loadYaml(await pubspec.readAsString());
    if (yamlContent is Map && yamlContent['dependencies'] is Map) {
      return List<String>.from((yamlContent['dependencies'] as Map).keys);
    }
    return [];
  }

  Future<CodeMap> _buildCodeMap(Map<String, dynamic> config) async {
    final modules = <Module>[];
    final relationships = <String, List<String>>{};
    final includePaths =
        List<String>.from(config['include'] as List? ?? ['lib']);
    final excludePaths = List<String>.from(config['exclude'] as List? ?? []);

    await for (final entity in Directory(projectPath).list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relativePath = entity.path.replaceFirst('$projectPath/', '');
        if (excludePaths.any(relativePath.startsWith)) continue;
        if (!includePaths.any(relativePath.startsWith)) {
          continue;
        }

        final module =
            await _parseDartFile(entity, relativePath, relationships);
        if (module != null) {
          modules.add(module);
          if (module.dependencies.isNotEmpty) {
            relationships[relativePath] = module.dependencies;
          }
        }
      }
    }

    return CodeMap(
      project: projectPath.split(Platform.pathSeparator).last,
      modules: modules,
      relationships:
          config['include_relationships'] == 'true' ? relationships : {},
      dependencies: config['include_dependencies'] == 'true'
          ? await _getDirectDependencies()
          : [],
    );
  }

  Future<Module?> _parseDartFile(
    File file,
    String relativePath,
    Map<String, List<String>> relationships,
  ) async {
    final content = await file.readAsString();

    // Preprocess to remove comments
    final processedContent = _preprocessContent(content);

    final dependencies = <String>[];
    final classes = <CodeElement>[];
    final constructors = <CodeElement>[];
    final functions = <CodeElement>[];
    final classNames = <String>{};
    final functionSignatures = <String>{};
    final constructorSignatures = <String>{};

    final importPattern = RegExp(
      r'import\s+(['
      '"])([^'
      '"]+)(['
      // ignore: unnecessary_string_escapes
      '"])((?:\s+(?:as|show|hide)\s+[^;]+)?);',
      caseSensitive: false,
    );

    // Extract all imports
    for (final match in importPattern.allMatches(processedContent)) {
      final importPath = match.group(2)!;
      final depFile = importPath.split('/').last;
      if (depFile.endsWith('.dart')) {
        dependencies.add(depFile);
      }
    }

    final classPattern = RegExp(
      r'(?:class|abstract\s+class)\s+(\w+)\s*(?:(extends|implements|with)\s*(\w+))?\s*(?:\{|\s)',
      caseSensitive: false,
    );

    for (final match in classPattern.allMatches(processedContent)) {
      final className = match.group(1)!;
      classNames.add(className);

      classes.add(
        CodeElement(
          name: className,
          signature: 'class $className',
        ),
      );

      final relationshipType = match.group(2);
      final relatedClass = match.group(3);
      if (relatedClass != null && relationshipType != null) {
        final classKey = '$relativePath:$className';
        relationships[classKey] = [relatedClass];
      }
    }

    // Helper to normalize parameters
    String normalizeParams(String params) {
      return params.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    // Check if a position is likely inside a function body
    bool isLikelyInFunctionBody(String text, int position) {
      var openBraces = 0;
      for (var i = 0; i < position && i < text.length; i++) {
        if (text[i] == '{') {
          openBraces++;
        } else if (text[i] == '}') {
          openBraces--;
        }
      }
      return openBraces > 0;
    }

    // Constructor pattern with optional super call
    final constructorPattern = RegExp(
      r'(const\s+)?(\w+)(?:\.(\w+))?\s*\(\s*((?:\{(?:[\w\s,=<>[\].]+(?:\s*=\s*[^{};]+)?(?:,|(?=\})))+\})?|[^{};]*)\s*\)\s*(?:\s*:\s*(super\s*\([^)]*\))?[^;{]*)(?:\s*\{|\s*;)',
      multiLine: true,
      caseSensitive: false,
    );

    final factoryConstructorPattern = RegExp(
      r'factory\s+(\w+)(?:\.(\w+))?\s*\(\s*((?:\{(?:[\w\s,=<>[\].]+(?:\s*=\s*[^{};]+)?(?:,|(?=\})))+\})?|[^{};]*)\s*\)(?:\s*(?:\{|=>))',
      multiLine: true,
      caseSensitive: false,
    );

    final processedConstructors = <String>{};

    for (final match in constructorPattern.allMatches(processedContent)) {
      final constKeyword = match.group(1)?.trim() ?? '';
      final className = match.group(2)!;
      final constructorName = match.group(3);
      final params = normalizeParams(match.group(4) ?? '');
      final superCall = match.group(5); // Captures : super(...)

      if (classNames.contains(className) &&
          !isLikelyInFunctionBody(processedContent, match.start)) {
        final signature = constructorName != null
            // ignore: lines_longer_than_80_chars
            ? '$constKeyword$className.$constructorName($params)${superCall != null ? ' : $superCall' : ''}'
            // ignore: lines_longer_than_80_chars
            : '$constKeyword$className($params)${superCall != null ? ' : $superCall' : ''}';

        if (!constructorSignatures.contains(signature)) {
          constructorSignatures.add(signature);
          constructors.add(
            CodeElement(
              name: className,
              signature: signature,
            ),
          );
          processedConstructors.add(
            constructorName != null ? '$className.$constructorName' : className,
          );
        }
      }
    }

    for (final match
        in factoryConstructorPattern.allMatches(processedContent)) {
      final className = match.group(1)!;
      final constructorName = match.group(2);
      if (classNames.contains(className)) {
        final params = normalizeParams(match.group(3) ?? '');
        final signature = constructorName != null
            ? 'factory $className.$constructorName($params)'
            : 'factory $className($params)';

        if (!constructorSignatures.contains(signature)) {
          constructorSignatures.add(signature);
          constructors.add(
            CodeElement(
              name: className,
              signature: signature,
            ),
          );
          processedConstructors.add(
            constructorName != null ? '$className.$constructorName' : className,
          );
        }
      }
    }

    // Split by lines for function processing
    final lines = processedContent.split('\n');

    // Function pattern for declarations only
    final functionPattern = RegExp(
      r'(?:(void|[\w<>\[\]]+(?:\s*<\s*[\w<>\[\]]+\s*>)?)\s+)?(\w+)\s*\(([^)]*)\)\s*(?:->\s*([\w<>\[\]]+(?:\s*<\s*[\w<>\[\]]+\s*>)?))?\s*(?:\{|=>)',
      multiLine: true,
      caseSensitive: false,
    );

    final exclusionPattern =
        RegExp(r'\b(?:catch|if|while|for|switch|return|else|super)\b');
    final invalidReturnTypes = {
      'await',
      'async',
      'const',
      'final',
      'var',
      'late',
      'static',
      'return',
    };

    // Sanitize return type helper
    String sanitizeReturnType(String? rawType) {
      if (rawType == null || invalidReturnTypes.contains(rawType)) {
        return 'dynamic';
      }
      return rawType.replaceAll(RegExp('[<>]'), '').trim();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (!exclusionPattern.hasMatch(line)) {
        final funcMatch = functionPattern.firstMatch(line);
        if (funcMatch != null) {
          final returnTypeRaw = funcMatch.group(1)?.trim();
          final funcName = funcMatch.group(2)!;
          final params = normalizeParams(funcMatch.group(3) ?? '');
          final explicitReturnType = funcMatch.group(4); // -> return type

          // Skip if it’s a class name or constructor
          if (classNames.contains(funcName) ||
              processedConstructors.contains(funcName)) {
            continue;
          }

          // Skip if it’s a lambda or method call argument
          final precedingText = i > 0 ? '${lines[i - 1].trim()} $line' : line;
          if (precedingText.contains(RegExp(r'\.\s*\w+\s*\(')) || // e.g., .map(
              line.startsWith('(') || // Starts with ( like a lambda
              (i > 0 && lines[i - 1].trim().endsWith('('))) {
            // Previous line ends with (
            continue;
          }

          final fullSignature = '$funcName($params)';
          if (functionSignatures.contains(fullSignature)) continue;
          functionSignatures.add(fullSignature);

          // Sanitize the return type
          String returnType;
          if (explicitReturnType != null) {
            returnType = sanitizeReturnType(explicitReturnType);
          } else if (returnTypeRaw != null &&
              !invalidReturnTypes.contains(returnTypeRaw)) {
            returnType = sanitizeReturnType(returnTypeRaw);
          } else {
            returnType = 'dynamic';
          }

          functions.add(
            CodeElement(
              name: funcName,
              signature: '$funcName($params) -> $returnType',
            ),
          );
        }
      }
    }

    // Update class signatures with constructor info
    for (var i = 0; i < classes.length; i++) {
      final className = classes[i].name;
      final classConstructors =
          constructors.where((c) => c.name == className).toList();

      if (classConstructors.isNotEmpty) {
        final constructorSignatures =
            classConstructors.map((c) => c.signature).join(', ');
        classes[i] = CodeElement(
          name: className,
          signature: classConstructors.length > 1
              ? 'class $className with constructors: $constructorSignatures'
              // ignore: lines_longer_than_80_chars
              : 'class $className with constructor: ${classConstructors[0].signature}',
        );
      }
    }

    if (classes.isEmpty && constructors.isEmpty && functions.isEmpty) {
      return null;
    }

    return Module(
      name: relativePath,
      classes: classes,
      constructors: {...constructors}.toList(),
      functions: {...functions}.toList(),
      dependencies: {...dependencies}.toList(),
    );
  }

  String _preprocessContent(String content) {
    final processed = content.replaceAllMapped(
      RegExp(r'/\*[\s\S]*?\*/', multiLine: true),
      (match) => '\n' * '\n'.allMatches(match.group(0)!).length,
    );

    return processed.replaceAllMapped(
      RegExp(r'//.*$', multiLine: true),
      (match) => ' ' * match.group(0)!.length,
    );
  }
}
