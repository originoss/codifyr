/// Codifyr - A CLI tool for generating LLM-friendly codemaps for Flutter projects.
///
/// This library provides tools to analyze Dart/Flutter projects and generate
/// structured representations optimized for Large Language Models (LLMs).
///
/// ```sh
/// # activate codifyr
/// dart pub global activate codifyr
///
/// # generate a codemap
/// codifyr generate --output codemap.json
///
/// # see all commands
/// codifyr --help
/// ```
library codifyr;

export 'src/codemap/code_map_generator.dart';
export 'src/codemap/token_estimator.dart';
