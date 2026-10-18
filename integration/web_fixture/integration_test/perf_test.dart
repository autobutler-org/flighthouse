import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_fixture/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final route in ['/perf/control', '/perf/janky']) {
    testWidgets('watches the frames of $route', (tester) async {
      await tester.pumpWidget(const FixtureApp(semantics: null));
      await tester.pumpAndSettle();

      await binding.watchPerformance(() async {
        unawaited(
          tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route),
        );
        await tester.pumpAndSettle();
      }, reportKey: route.substring(1).replaceAll('/', '-'));
    });
  }
}
