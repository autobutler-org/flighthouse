/// The outcome of a computation that can fail: an [Ok] value or an [Err].
///
/// Pipeline functions return a [Result] instead of throwing, so every failure
/// is visible in the type and handled with an exhaustive `switch`.
sealed class Result<T, E> {
  /// Base constructor for [Ok] and [Err].
  const Result();

  /// Applies [onOk] to an [Ok] value or [onErr] to an [Err] error.
  R fold<R>(R Function(T value) onOk, R Function(E error) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final error) => onErr(error),
      };

  /// Transforms an [Ok] value, leaving an [Err] unchanged.
  Result<U, E> map<U>(U Function(T value) transform) =>
      fold((value) => Ok(transform(value)), Err.new);

  /// Transforms an [Err] error, leaving an [Ok] unchanged.
  Result<T, F> mapErr<F>(F Function(E error) transform) =>
      fold(Ok.new, (error) => Err(transform(error)));

  /// Chains a computation that can itself fail onto an [Ok] value.
  Result<U, E> flatMap<U>(Result<U, E> Function(T value) next) =>
      fold(next, Err.new);
}

/// A successful [Result] holding [value].
final class Ok<T, E> extends Result<T, E> {
  /// Wraps [value] as a success.
  const Ok(this.value);

  /// The successful value.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, E> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// A failed [Result] holding [error].
final class Err<T, E> extends Result<T, E> {
  /// Wraps [error] as a failure.
  const Err(this.error);

  /// The failure.
  final E error;

  @override
  bool operator ==(Object other) => other is Err<T, E> && other.error == error;

  @override
  int get hashCode => Object.hash(Err, error);

  @override
  String toString() => 'Err($error)';
}

/// Applies [transform] to each item, returning every value or the first error.
///
/// Stops at the first [Err]. The returned list is unmodifiable.
Result<List<B>, E> traverse<A, B, E>(
  Iterable<A> items,
  Result<B, E> Function(A item) transform,
) {
  final values = <B>[];
  for (final item in items) {
    switch (transform(item)) {
      case Ok(:final value):
        values.add(value);
      case Err(:final error):
        return Err(error);
    }
  }
  return Ok(List.unmodifiable(values));
}

/// Splits [results] into their values and their errors, keeping order.
///
/// Use it where a stage should keep going past a bad input and report every
/// failure. Both returned lists are unmodifiable.
(List<T> values, List<E> errors) partition<T, E>(
  Iterable<Result<T, E>> results,
) => _splitResults(results.toList(growable: false));

(List<T> values, List<E> errors) _splitResults<T, E>(
  List<Result<T, E>> results,
) => (
  List.unmodifiable([
    for (final result in results)
      if (result case Ok(:final value)) value,
  ]),
  List.unmodifiable([
    for (final result in results)
      if (result case Err(:final error)) error,
  ]),
);
