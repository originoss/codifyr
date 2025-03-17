import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:codifyr/src/codemap/code_map_generator.dart';
import 'package:codifyr/src/codemap/token_estimator.dart';
import 'package:mason_logger/mason_logger.dart';

/// {@template generate_command}
///
/// `codifyr generate`
/// A [Command] to generate LLM-friendly codemaps for a project
/// {@endtemplate}
class GenerateCommand extends Command<int> {
  /// {@macro generate_command}
  GenerateCommand({
    required Logger logger,
  }) : _logger = logger {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Path to output JSON file',
        defaultsTo: 'codemap.json',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to configuration file',
        defaultsTo: 'codifyr.yaml',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose output',
        negatable: false,
      );
  }

  @override
  String get description => 'Generate LLM-friendly codemaps for a project';

  @override
  String get name => 'generate';

  final Logger _logger;

  @override
  Future<int> run() async {
    final projectPath = Directory.current.path;
    final outputPath = argResults?['output'] as String;
    final configPath = argResults?['config'] as String;
    final verbose = argResults?['verbose'] as bool;

    if (verbose) {
      _logger
        ..info('Project path: $projectPath')
        ..info('Output path: $outputPath')
        ..info('Config path: $configPath');
    }

    final progress = _logger.progress('Generating codemap');

    try {
      final generator = CodeMapGenerator(
        projectPath: projectPath,
        outputJsonPath: outputPath,
        configPath: configPath,
      );

      final codemap = await generator.generateCodeMap();
      final tokenCount = estimateTokenCount(codemap);

      progress.complete('Codemap generated successfully');
      _logger
        ..info('Output written to: $outputPath')
        ..info('Estimated token count: $tokenCount');

      return ExitCode.success.code;
    } catch (e) {
      progress.fail('Failed to generate codemap');
      _logger.err('Error: $e');
      return ExitCode.software.code;
    }
  }
}
