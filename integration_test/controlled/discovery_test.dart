import 'package:corevent_mobile_app/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../support/app_harness.dart';
import '../support/fixture_backend.dart';
import '../support/ui_actions.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  });
  setUp(clearFixtureSession);
  tearDown(clearFixtureSession);

  testWidgets('busca e prévia recuperam falha nos detalhes', (tester) async {
    await seedSession();
    final backend = FixtureBackend();
    final container = await openApp(tester, backend);
    await tapFixture(tester, find.text('Explorar').last);
    await tester.pumpAndSettle();
    await waitForFixtureText(tester, 'Festival de integração');
    await enterFixtureText(tester, find.byType(TextField).first, 'Festival');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitForFixtureText(tester, 'Festival de integração');
    expect(
      backend.requests.any(
        (request) =>
            request.path == '/api/events' &&
            request.queryParameters['search'] == 'Festival',
      ),
      isTrue,
    );

    backend.failNextEventDetail = true;
    await tester.ensureVisible(find.text('Festival de integração').last);
    await tapFixture(tester, find.text('Festival de integração').last);
    await tester.pumpAndSettle();
    expect(find.text('Prévia do evento'), findsOneWidget);
    // The description is built lazily below the banner on small displays.
    await tester.scrollUntilVisible(
      find.text('Não foi possível carregar a descrição deste evento.'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.text('Não foi possível carregar a descrição deste evento.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Tentar novamente'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tapFixture(tester, find.text('Tentar novamente').last);
    await tester.pumpAndSettle();
    expect(find.text('Evento de integração'), findsOneWidget);
    backend.expectOnlySupportedRequests();
    await closeApp(tester, container);
  });

  testWidgets('favorito criado na prévia aparece na conta', (tester) async {
    await seedSession();
    final backend = FixtureBackend();
    final container = await openApp(tester, backend);
    await tapFixture(tester, find.text('Explorar').last);
    await tester.pumpAndSettle();
    await waitForFixtureText(tester, 'Festival de integração');
    await tester.ensureVisible(find.text('Festival de integração').last);
    await tapFixture(tester, find.text('Festival de integração').last);
    await waitForFixtureText(tester, 'Favoritar');
    await tester.ensureVisible(find.text('Favoritar').last);
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
    await closeApp(tester, container);
  });
}
