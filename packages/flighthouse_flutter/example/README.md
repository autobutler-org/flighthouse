# Example

Add the package as a dev dependency of the Flutter app that `flighthouse` reports on:

```sh
flutter pub add --dev flighthouse_flutter
```

Then import it from an integration test:

```dart
import 'package:flighthouse_flutter/flighthouse_flutter.dart';
```

The package exports no API yet. The helper that writes `integration_test` frame timings where
`flighthouse collect` reads them is tracked in
[issue #31](https://github.com/autobutler-org/flighthouse/issues/31).
