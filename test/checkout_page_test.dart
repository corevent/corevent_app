import 'dart:async';

import 'package:corevent_mobile_app/features/auth/data/auth_dtos.dart';
import 'package:corevent_mobile_app/features/auth/presentation/auth_session.dart';
import 'package:corevent_mobile_app/features/checkout/data/checkout_dtos.dart';
import 'package:corevent_mobile_app/features/checkout/data/checkout_repository.dart';
import 'package:corevent_mobile_app/features/checkout/presentation/checkout_page.dart';
import 'package:corevent_mobile_app/features/events/data/event_dtos.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

class MockCheckoutRepository extends Mock implements CheckoutRepository {}

class MockPendingStore extends Mock implements PendingCheckoutStore {}

class MockSession extends Mock implements AuthSession {}

CheckoutCatalog catalog({bool adultOnly = false, double price = 25}) {
  final now = DateTime.now();
  return CheckoutCatalog(
    EventDetail(
      id: 'e1',
      title: 'Festival de música',
      startDate: now.add(const Duration(days: 2)),
      endDate: now.add(const Duration(days: 2, hours: 3)),
      category: 'music',
      isAdultOnly: adultOnly,
      locationName: 'Arena',
      organizer: const EventOrganizer(name: 'Organizador'),
      status: 'opened',
    ),
    [
      CheckoutTicketType(
        id: 'paid',
        name: 'Inteira',
        price: price,
        availableQuantity: 2,
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      ),
    ],
  );
}

GoRouter router() => GoRouter(
  initialLocation: '/checkout',
  routes: [
    GoRoute(
      path: '/checkout',
      builder: (_, _) => const CheckoutPage(eventId: 'e1'),
    ),
    GoRoute(
      path: '/orders/:id/status',
      builder: (_, state) =>
          Scaffold(body: Text('Status ${state.pathParameters['id']}')),
    ),
    GoRoute(
      path: '/profile/orders',
      builder: (_, _) => const Scaffold(body: Text('Meus pedidos')),
    ),
    GoRoute(
      path: '/home',
      builder: (_, _) => const Scaffold(body: Text('Início')),
    ),
  ],
);

Finder iconButtonWithTooltip(String tooltip) => find
    .ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton))
    .first;

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  late MockCheckoutRepository repository;
  late MockPendingStore store;
  late MockSession session;
  late GoRouter appRouter;

  setUp(() {
    repository = MockCheckoutRepository();
    store = MockPendingStore();
    session = MockSession();
    appRouter = router();
    when(() => session.user).thenReturn(
      const UserProfile(
        id: 'u1',
        name: 'Ana',
        email: 'ana@example.com',
        birthDate: '2000-01-01',
      ),
    );
    when(() => repository.catalog('e1')).thenAnswer((_) async => catalog());
    when(() => store.save('u1', 'o1')).thenAnswer((_) async {});
  });

  tearDown(() => appRouter.dispose());

  Future<void> show(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          checkoutRepositoryProvider.overrideWithValue(repository),
          pendingCheckoutStoreProvider.overrideWithValue(store),
          authSessionProvider.overrideWithValue(session),
        ],
        child: MaterialApp.router(
          routerConfig: appRouter,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('seleção atualiza total e só permite continuar com ingresso', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Festival de música'), findsOneWidget);
    expect(find.text('0 ingressos'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Continuar'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Adicionar Inteira'));
    await tester.pump();
    expect(find.text('1 ingresso'), findsOneWidget);
    expect(find.textContaining('25,00'), findsWidgets);
    await tester.tap(find.byTooltip('Adicionar Inteira'));
    await tester.pump();
    expect(find.text('2 ingressos'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(iconButtonWithTooltip('Adicionar Inteira'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Continuar exibe política +18 e só cria pedido após aceite', (
    tester,
  ) async {
    const policy = AgePolicy('p1', 'Termos de idade', 1);
    when(() => repository.catalog('e1'))
        .thenAnswer((_) async => catalog(adultOnly: true));
    when(() => repository.agePolicyStatus())
        .thenAnswer((_) async => (policy: policy, accepted: false));
    when(() => repository.requiredAgePolicy()).thenAnswer((_) async => policy);
    when(() => repository.acceptAgePolicy()).thenAnswer((_) async {});
    when(() => repository.create('e1', {'paid': 1}))
        .thenAnswer((_) async => const CreatedOrder('o1', [], []));
    await show(tester);
    expect(find.textContaining('você precisa ler e aceitar'), findsOneWidget);
    await tester.tap(find.byTooltip('Adicionar Inteira'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmação de idade'), findsOneWidget);
    expect(find.text('Termos de idade'), findsOneWidget);
    verifyNever(() => repository.create(any(), any()));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    verifyNever(() => repository.acceptAgePolicy());
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Li e aceito'));
    await tester.pumpAndSettle();
    expect(find.text('Status o1'), findsOneWidget);
    verify(() => repository.acceptAgePolicy()).called(1);
    verify(() => repository.create('e1', {'paid': 1})).called(1);
  });

  testWidgets('envio bloqueia seleção e navega ao status uma única vez', (
    tester,
  ) async {
    final pendingOrder = Completer<CreatedOrder>();
    when(() => repository.create('e1', {'paid': 1}))
        .thenAnswer((_) => pendingOrder.future);
    await show(tester);
    await tester.tap(find.byTooltip('Adicionar Inteira'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(iconButtonWithTooltip('Adicionar Inteira'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(iconButtonWithTooltip('Voltar')).onPressed,
      isNull,
    );
    expect(find.text('Status o1'), findsNothing);

    pendingOrder.complete(const CreatedOrder('o1', [], []));
    await tester.pumpAndSettle();
    expect(find.text('Status o1'), findsOneWidget);
    verify(() => repository.create('e1', {'paid': 1})).called(1);
  });

  testWidgets('timeout incerto orienta consultar pedidos sem repetir POST', (
    tester,
  ) async {
    when(() => repository.create('e1', {'paid': 1})).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        type: DioExceptionType.receiveTimeout,
      ),
    );
    await show(tester);
    await tester.tap(find.byTooltip('Adicionar Inteira'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Consultar meus pedidos'), findsOneWidget);
    expect(find.text('Continuar'), findsNothing);
    verify(() => repository.create('e1', {'paid': 1})).called(1);
  });

  for (final free in [true, false]) {
    testWidgets(
      'Voltar após pedido ${free ? 'gratuito' : 'pago'} retorna à origem',
      (tester) async {
        when(() => repository.catalog('e1'))
            .thenAnswer((_) async => catalog(price: free ? 0 : 25));
        when(() => repository.create('e1', {'paid': 1})).thenAnswer(
          (_) async => CreatedOrder('o1', [
            if (!free)
              const CheckoutPaymentLink(
                'PAY',
                'https://payment.example',
                'GET',
              ),
          ], []),
        );
        await show(tester);
        appRouter.go('/home');
        await tester.pumpAndSettle();
        unawaited(appRouter.push('/checkout'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Adicionar Inteira'));
        await tester.pump();
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.text('Status o1'), findsOneWidget);

        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Início'), findsOneWidget);
        expect(find.text('Escolher ingressos'), findsNothing);
        verify(() => repository.create('e1', {'paid': 1})).called(1);
      },
    );
  }

  for (final scale in [1.5, 2.0]) {
    testWidgets('layout de checkout rola em 360px com fonte $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, textScale: scale);
      expect(find.text('Escolher ingressos'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
