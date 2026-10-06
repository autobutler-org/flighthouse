import '../model/enums.dart';
import '../model/observations.dart';

/// One raw output file from a tool, read by the shell.
typedef RawArtifact = ({Source source, String path, String contents});

/// What an adapter extracted from one raw artifact.
///
/// Routes and targets are as the tool reported them; the normalize stage
/// rewrites them and recomputes fingerprints.
final class AdapterOutput {
  /// Output holding unmodifiable copies of the given lists.
  AdapterOutput({
    required this.toolVersion,
    required List<Finding> findings,
    required List<RuleOutcome> ruleOutcomes,
    required List<Measurement> measurements,
  }) : findings = List.unmodifiable(findings),
       ruleOutcomes = List.unmodifiable(ruleOutcomes),
       measurements = List.unmodifiable(measurements);

  /// The version of the tool that wrote the artifact.
  final String toolVersion;

  /// Every failure found.
  final List<Finding> findings;

  /// Every rule checked, passing or not.
  final List<RuleOutcome> ruleOutcomes;

  /// Every metric measured.
  final List<Measurement> measurements;
}
