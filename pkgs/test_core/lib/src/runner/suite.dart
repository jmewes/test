// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:boolean_selector/boolean_selector.dart';
import 'package:collection/collection.dart';
import 'package:source_span/source_span.dart';
import 'package:test_api/scaffolding.dart' // ignore: deprecated_member_use
    show
        Timeout;
import 'package:test_api/src/backend/metadata.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/platform_selector.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/runtime.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/suite_platform.dart'; // ignore: implementation_imports

import 'runtime_selection.dart';

/// Suite-level configuration.
///
/// This tracks configuration that can differ from suite to suite.
class SuiteConfiguration {
  /// Empty configuration with only default values.
  ///
  /// Using this is slightly more efficient than manually constructing a new
  /// configuration with no arguments.
  static final empty = SuiteConfiguration._();

  /// Whether JavaScript stack traces should be left as-is or converted to
  /// Dart-like traces.
  bool get jsTrace => _jsTrace ?? false;
  final bool? _jsTrace;

  /// Whether skipped tests should be run.
  bool get runSkipped => _runSkipped ?? false;
  final bool? _runSkipped;

  /// The path to a mirror of this package containing HTML that points to
  /// precompiled JS.
  ///
  /// This is used by the internal Google test runner so that test compilation
  /// can more effectively make use of Google's build tools.
  final String? precompiledPath;

  /// Additional arguments to pass to dart2js.
  ///
  /// Note that this if multiple suites run the same JavaScript on different
  /// runtimes, and they have different [dart2jsArgs], only one (undefined)
  /// suite's arguments will be used.
  final List<String> dart2jsArgs;

  /// The patterns to match against test names to decide which to run.
  ///
  /// All patterns must match in order for a test to be run.
  ///
  /// If empty, all tests should be run.
  final Set<Pattern> patterns;

  /// The set of runtimes on which to run tests.
  List<String> get runtimes => _runtimes == null
      ? const ['vm']
      : List.unmodifiable(_runtimes!.map((runtime) => runtime.name));
  final List<RuntimeSelection>? _runtimes;

  /// Only run tests whose tags match this selector.
  ///
  /// When [merge]d, this is intersected with the other configuration's included
  /// tags.
  final BooleanSelector includeTags;

  /// Do not run tests whose tags match this selector.
  ///
  /// When [merge]d, this is unioned with the other configuration's
  /// excluded tags.
  final BooleanSelector excludeTags;

  /// Configuration for particular tags.
  ///
  /// The keys are tag selectors, and the values are configurations for tests
  /// whose tags match those selectors.
  final Map<BooleanSelector, SuiteConfiguration> tags;

  /// Configuration for particular platforms.
  ///
  /// The keys are platform selectors, and the values are configurations for
  /// those platforms. These configuration should only contain test-level
  /// configuration fields, but that isn't enforced.
  final Map<PlatformSelector, SuiteConfiguration> onPlatform;

  /// The seed with which to shuffle the test order.
  /// Default value is null if not provided and will not change the test order.
  /// The same seed will shuffle the tests in the same way every time.
  final int? testRandomizeOrderingSeed;

  /// The global test metadata derived from this configuration.
  Metadata get metadata {
    if (tags.isEmpty && onPlatform.isEmpty) return _metadata;
    return _metadata.change(
        forTag: tags.map((key, config) => MapEntry(key, config.metadata)),
        onPlatform:
            onPlatform.map((key, config) => MapEntry(key, config.metadata)));
  }

  final Metadata _metadata;

  /// The set of tags that have been declared in any way in this configuration.
  Set<String> get knownTags {
    if (_knownTags != null) return _knownTags!;

    var known = includeTags.variables.toSet()
      ..addAll(excludeTags.variables)
      ..addAll(_metadata.tags);

    for (var selector in tags.keys) {
      known.addAll(selector.variables);
    }

    for (var configuration in _children) {
      known.addAll(configuration.knownTags);
    }

    return _knownTags = UnmodifiableSetView(known);
  }

  Set<String>? _knownTags;

  /// All child configurations that may be selected under various circumstances.
  Iterable<SuiteConfiguration> get _children sync* {
    yield* tags.values;
    yield* onPlatform.values;
  }

  factory SuiteConfiguration(
      {bool? jsTrace,
      bool? runSkipped,
      Iterable<String>? dart2jsArgs,
      String? precompiledPath,
      Iterable<Pattern>? patterns,
      Iterable<RuntimeSelection>? runtimes,
      BooleanSelector? includeTags,
      BooleanSelector? excludeTags,
      Map<BooleanSelector, SuiteConfiguration>? tags,
      Map<PlatformSelector, SuiteConfiguration>? onPlatform,
      int? testRandomizeOrderingSeed,

      // Test-level configuration
      Timeout? timeout,
      bool? verboseTrace,
      bool? chainStackTraces,
      bool? skip,
      int? retry,
      String? skipReason,
      PlatformSelector? testOn,
      Iterable<String>? addTags}) {
    var config = SuiteConfiguration._(
        jsTrace: jsTrace,
        runSkipped: runSkipped,
        dart2jsArgs: dart2jsArgs,
        precompiledPath: precompiledPath,
        patterns: patterns,
        runtimes: runtimes,
        includeTags: includeTags,
        excludeTags: excludeTags,
        tags: tags,
        onPlatform: onPlatform,
        testRandomizeOrderingSeed: testRandomizeOrderingSeed,
        metadata: Metadata(
            timeout: timeout,
            verboseTrace: verboseTrace,
            chainStackTraces: chainStackTraces,
            skip: skip,
            retry: retry,
            skipReason: skipReason,
            testOn: testOn,
            tags: addTags));
    return config._resolveTags();
  }

  /// Creates new SuiteConfiguration.
  ///
  /// Unlike [new SuiteConfiguration], this assumes [tags] is already
  /// resolved.
  SuiteConfiguration._(
      {bool? jsTrace,
      bool? runSkipped,
      Iterable<String>? dart2jsArgs,
      this.precompiledPath,
      Iterable<Pattern>? patterns,
      Iterable<RuntimeSelection>? runtimes,
      BooleanSelector? includeTags,
      BooleanSelector? excludeTags,
      Map<BooleanSelector, SuiteConfiguration>? tags,
      Map<PlatformSelector, SuiteConfiguration>? onPlatform,
      int? testRandomizeOrderingSeed,
      Metadata? metadata})
      : _jsTrace = jsTrace,
        _runSkipped = runSkipped,
        dart2jsArgs = _list(dart2jsArgs) ?? const [],
        patterns = UnmodifiableSetView(patterns?.toSet() ?? {}),
        _runtimes = _list(runtimes),
        includeTags = includeTags ?? BooleanSelector.all,
        excludeTags = excludeTags ?? BooleanSelector.none,
        tags = _map(tags),
        onPlatform = _map(onPlatform),
        testRandomizeOrderingSeed = testRandomizeOrderingSeed,
        _metadata = metadata ?? Metadata.empty;

  /// Creates a new [SuiteConfiguration] that takes its configuration from
  /// [metadata].
  factory SuiteConfiguration.fromMetadata(Metadata metadata) =>
      SuiteConfiguration._(
          tags: metadata.forTag.map((key, child) =>
              MapEntry(key, SuiteConfiguration.fromMetadata(child))),
          onPlatform: metadata.onPlatform.map((key, child) =>
              MapEntry(key, SuiteConfiguration.fromMetadata(child))),
          metadata: metadata.change(forTag: {}, onPlatform: {}));

  /// Returns an unmodifiable copy of [input].
  ///
  /// If [input] is `null` or empty, this returns `null`.
  static List<T>? _list<T>(Iterable<T>? input) {
    if (input == null) return null;
    var list = List<T>.unmodifiable(input);
    if (list.isEmpty) return null;
    return list;
  }

  /// Returns an unmodifiable copy of [input] or an empty unmodifiable map.
  static Map<K, V> _map<K, V>(Map<K, V>? input) {
    if (input == null || input.isEmpty) return const <Never, Never>{};
    return Map.unmodifiable(input);
  }

  /// Merges this with [other].
  ///
  /// For most fields, if both configurations have values set, [other]'s value
  /// takes precedence. However, certain fields are merged together instead.
  /// This is indicated in those fields' documentation.
  SuiteConfiguration merge(SuiteConfiguration other) {
    if (this == SuiteConfiguration.empty) return other;
    if (other == SuiteConfiguration.empty) return this;

    var config = SuiteConfiguration._(
        jsTrace: other._jsTrace ?? _jsTrace,
        runSkipped: other._runSkipped ?? _runSkipped,
        dart2jsArgs: dart2jsArgs.toList()..addAll(other.dart2jsArgs),
        precompiledPath: other.precompiledPath ?? precompiledPath,
        patterns: patterns.union(other.patterns),
        runtimes: other._runtimes ?? _runtimes,
        includeTags: includeTags.intersection(other.includeTags),
        excludeTags: excludeTags.union(other.excludeTags),
        tags: _mergeConfigMaps(tags, other.tags),
        onPlatform: _mergeConfigMaps(onPlatform, other.onPlatform),
        testRandomizeOrderingSeed:
            other.testRandomizeOrderingSeed ?? testRandomizeOrderingSeed,
        metadata: metadata.merge(other.metadata));
    return config._resolveTags();
  }

  /// Returns a copy of this configuration with the given fields updated.
  ///
  /// Note that unlike [merge], this has no merging behavior—the old value is
  /// always replaced by the new one.
  SuiteConfiguration change(
      {bool? jsTrace,
      bool? runSkipped,
      Iterable<String>? dart2jsArgs,
      String? precompiledPath,
      Iterable<Pattern>? patterns,
      Iterable<RuntimeSelection>? runtimes,
      BooleanSelector? includeTags,
      BooleanSelector? excludeTags,
      Map<BooleanSelector, SuiteConfiguration>? tags,
      Map<PlatformSelector, SuiteConfiguration>? onPlatform,
      int? testRandomizeOrderingSeed,

      // Test-level configuration
      Timeout? timeout,
      bool? verboseTrace,
      bool? chainStackTraces,
      bool? skip,
      int? retry,
      String? skipReason,
      PlatformSelector? testOn,
      Iterable<String>? addTags}) {
    var config = SuiteConfiguration._(
        jsTrace: jsTrace ?? _jsTrace,
        runSkipped: runSkipped ?? _runSkipped,
        dart2jsArgs: dart2jsArgs?.toList() ?? this.dart2jsArgs,
        precompiledPath: precompiledPath ?? this.precompiledPath,
        patterns: patterns ?? this.patterns,
        runtimes: runtimes ?? _runtimes,
        includeTags: includeTags ?? this.includeTags,
        excludeTags: excludeTags ?? this.excludeTags,
        tags: tags ?? this.tags,
        onPlatform: onPlatform ?? this.onPlatform,
        testRandomizeOrderingSeed:
            testRandomizeOrderingSeed ?? testRandomizeOrderingSeed,
        metadata: _metadata.change(
            timeout: timeout,
            verboseTrace: verboseTrace,
            chainStackTraces: chainStackTraces,
            skip: skip,
            retry: retry,
            skipReason: skipReason,
            testOn: testOn,
            tags: addTags?.toSet()));
    return config._resolveTags();
  }

  /// Throws a [FormatException] if this refers to any undefined runtimes.
  void validateRuntimes(List<Runtime> allRuntimes) {
    var validVariables =
        allRuntimes.map((runtime) => runtime.identifier).toSet();
    _metadata.validatePlatformSelectors(validVariables);

    var runtimes = _runtimes;
    if (runtimes != null) {
      for (var selection in runtimes) {
        if (!allRuntimes
            .any((runtime) => runtime.identifier == selection.name)) {
          if (selection.span != null) {
            throw SourceSpanFormatException(
                'Unknown platform "${selection.name}".', selection.span);
          } else {
            throw FormatException('Unknown platform "${selection.name}".');
          }
        }
      }
    }

    onPlatform.forEach((selector, config) {
      selector.validate(validVariables);
      config.validateRuntimes(allRuntimes);
    });
  }

  /// Returns a copy of this with all platform-specific configuration from
  /// [onPlatform] resolved.
  SuiteConfiguration forPlatform(SuitePlatform platform) {
    if (onPlatform.isEmpty) return this;

    var config = this;
    onPlatform.forEach((platformSelector, platformConfig) {
      if (!platformSelector.evaluate(platform)) return;
      config = config.merge(platformConfig);
    });
    return config.change(onPlatform: {});
  }

  /// Merges two maps whose values are [SuiteConfiguration]s.
  ///
  /// Any overlapping keys in the maps have their configurations merged in the
  /// returned map.
  Map<T, SuiteConfiguration> _mergeConfigMaps<T>(
          Map<T, SuiteConfiguration> map1, Map<T, SuiteConfiguration> map2) =>
      mergeMaps(map1, map2,
          value: (config1, config2) => config1.merge(config2));

  SuiteConfiguration _resolveTags() {
    // If there's no tag-specific configuration, or if none of it applies, just
    // return the configuration as-is.
    if (_metadata.tags.isEmpty || tags.isEmpty) return this;

    // Otherwise, resolve the tag-specific components.
    var newTags = Map<BooleanSelector, SuiteConfiguration>.from(tags);
    var merged = tags.keys.fold(empty, (SuiteConfiguration merged, selector) {
      if (!selector.evaluate(_metadata.tags.contains)) return merged;
      return merged.merge(newTags.remove(selector)!);
    });

    if (merged == empty) return this;
    return change(tags: newTags).merge(merged);
  }
}
