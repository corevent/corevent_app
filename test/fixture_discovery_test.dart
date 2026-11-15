import 'package:corevent_mobile_app/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../integration_test/support/app_harness.dart';
import '../integration_test/support/fixture_backend.dart';
import '../integration_test/support/ui_actions.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets(
    'favorito da prévia chega à conta usando contratos das fixtures',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedSession();
      final backend = FixtureBackend();
      final container = await openApp(tester, backend);
      addTearDown(() async {
        await closeApp(tester, container);
        await clearFixtureSession();
      });

      await tapFixture(tester, find.text('Explorar').last);
      await tester.pumpAndSettle();
      await waitForFixtureText(tester, 'Festival de integração');
      await tapFixture(tester, find.text('Festival de integração').last);
      await waitForFixtureText(tester, 'Favoritar');
      await tapFixture(tester, find.text('Favoritar').last);
      await waitForFixtureText(tester, 'Favoritado');
      expect(backend.favoriteSaved, isTrue);
      await tapFixture(tester, find.byTooltip('Fechar prévia'));
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/profile/favorites');
      await tester.pumpAndSettle();
      await waitForFixtureText(tester, 'Festival de integração');
      expect(find.text('Festival de integração'), findsWidgets);
      backend.expectOnlySupportedRequests();
    },
  );
}
