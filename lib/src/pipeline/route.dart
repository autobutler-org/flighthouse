import '../result/failure.dart';
import '../result/result.dart';

/// A route pattern in go_router syntax, such as `/files/:path(.*)`.
///
/// A plain `:name` parameter matches one path segment; `:name(regex)` matches
/// what its regular expression matches.
final class RoutePattern {
  const RoutePattern._(this.pattern, this._matcher, this._hasParameters);

  /// The pattern as written in config, used as the normalized route.
  final String pattern;

  final RegExp _matcher;

  final bool _hasParameters;

  /// Whether [path] is an instance of this pattern.
  bool matches(String path) => _matcher.hasMatch(path);
}

final _parameter = RegExp(r':(\w+)(\((?:[^()\\]|\\.|\([^()]*\))*\))?');

/// Compiles [pattern], reporting a problem against config key [keyPath].
Result<RoutePattern, ConfigFailure> compileRoutePattern(
  String pattern,
  String keyPath,
) {
  if (!pattern.startsWith('/')) {
    return Err(
      ConfigFailure(
        keyPath: keyPath,
        problem: 'a route pattern must start with "/"',
      ),
    );
  }
  final source = pattern.splitMapJoin(
    _parameter,
    onMatch: (match) => switch (match.group(2)) {
      final constraint? =>
        '(?:${constraint.substring(1, constraint.length - 1)})',
      null => '[^/]+',
    },
    onNonMatch: RegExp.escape,
  );
  try {
    return Ok(
      RoutePattern._(
        pattern,
        RegExp('^$source\$'),
        _parameter.hasMatch(pattern),
      ),
    );
  } on FormatException catch (error) {
    return Err(
      ConfigFailure(
        keyPath: keyPath,
        problem: 'invalid regular expression in "$pattern": ${error.message}',
      ),
    );
  }
}

String pathOf(String route) {
  final uri = Uri.tryParse(route);
  final path = uri != null && uri.hasScheme
      ? uri.path
      : route.split(RegExp('[?#]')).first;
  final trimmed = path.replaceFirst(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? '/' : trimmed;
}

/// The canonical form of [route] for fingerprints and grouping.
///
/// Takes a path or an absolute URL. Drops the scheme, host, query, fragment,
/// and trailing slashes, keeps case, and replaces a path matching one of
/// [patterns] with the first matching pattern. A route that already is a
/// pattern with parameters is returned unchanged, so normalizing twice
/// changes nothing.
String normalizeRoute(String route, List<RoutePattern> patterns) {
  if (patterns.any(
    (candidate) => candidate._hasParameters && candidate.pattern == route,
  )) {
    return route;
  }
  final path = pathOf(route);
  return patterns
          .where((candidate) => candidate.matches(path))
          .map((candidate) => candidate.pattern)
          .firstOrNull ??
      path;
}
