# Codifyr

[![Pub Version](https://img.shields.io/pub/v/codifyr)](https://pub.dev/packages/codifyr)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A CLI tool for generating LLM-friendly codemaps for Flutter projects. Codifyr helps you create structured representations of your codebase that are optimized for Large Language Models (LLMs).

## Features

- Generate comprehensive code maps of your Flutter/Dart projects
- Customize output with configuration options
- Estimate token counts for LLM context planning
- Exclude generated files and patterns
- Export to JSON format for easy consumption by LLMs

## Installation 🚀

```sh
dart pub global activate codifyr
```

Or locally via:

```sh
dart pub global activate --source=path <path to this package>
```

## Usage

### Command Line

```sh
# Generate a code map with default settings
codifyr generate

# Specify output path
codifyr generate --output my_codemap.json

# Use custom configuration file
codifyr generate --config my_config.yaml

# Enable verbose output
codifyr generate --verbose

# Update the CLI to the latest version
codifyr update
```

### Configuration

Create a `codifyr.yaml` file in your project root:

```yaml
include_relationships: false
include_dependencies: false
exclude:
  - "**/*.gr.dart"
  - "**/*.freezed.dart"
  - "**/*.g.dart"
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.