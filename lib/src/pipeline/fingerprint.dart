import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../model/enums.dart';

/// The fingerprint scheme version, part of every fingerprint's input.
///
/// Changing how fingerprints or their inputs are normalized bumps this, and
/// `flighthouse baseline --update` migrates a baseline to the new scheme.
const String fingerprintVersion = 'v1';

String escapeField(String field) =>
    field.replaceAll(r'\', r'\\').replaceAll('|', r'\|');

const String absentField = r'\N';

String fingerprintInput({
  required Source source,
  required String rule,
  required String route,
  required String? target,
}) => [
  fingerprintVersion,
  escapeField(source.id),
  escapeField(rule),
  escapeField(route),
  switch (target) {
    final value? => escapeField(value),
    null => absentField,
  },
].join('|');

/// The stable identity of a finding across runs, as 64 lowercase hex digits.
///
/// [route] and [target] must already be normalized. The finding's message is
/// deliberately not an input, so rewording it does not make a finding new.
String fingerprint({
  required Source source,
  required String rule,
  required String route,
  required String? target,
}) => sha256
    .convert(
      utf8.encode(
        fingerprintInput(
          source: source,
          rule: rule,
          route: route,
          target: target,
        ),
      ),
    )
    .toString();
