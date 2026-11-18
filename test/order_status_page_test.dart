import 'dart:async';

import 'package:corevent_mobile_app/core/theme/app_theme.dart';
import 'package:corevent_mobile_app/features/auth/presentation/auth_session.dart';
import 'package:corevent_mobile_app/features/checkout/data/checkout_dtos.dart';
import 'package:corevent_mobile_app/features/checkout/presentation/order_status_page.dart';
import 'package:corevent_mobile_app/features/profile/data/activity_dtos.dart';
import 'package:corevent_mobile_app/features/profile/data/activity_repository.dart';
import 'package:corevent_mobile_app/features/tickets/data/ticket_dtos.dart';
import 'package:corevent_mobile_app/features/tickets/data/tickets_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

class MockActivityRepository extends Mock implements ActivityRepository {}

class MockTicketsRepository extends Mock implements TicketsRepository {}

class MockSession extends Mock implements AuthSession {}

OrderDetails order(String status, {bool payment = false}) => OrderDetails(
  'o1',
  OrderEvent('e1', 'Festival de música', DateTime(2026, 10, 10)),
  25,
  status,
  DateTime(2026, 9, 30),
  const [],
  payment
      ? const OrderCheckout('checkout-1', 'created', [
          OrderCheckoutLink('PAY', 'https://payment.example/checkout', 'GET'),
        ])
      : null,
);

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  late MockActivityRepository activity;
  late MockTicketsRepository tickets;
  late MockSession session;
  late GoRouter router;

  setUp(() {
    activity = MockActivityRepository();
    tickets = MockTicketsRepository();
    session = MockSession();
    when(() => session.user).thenReturn(null);
    when(() => activity.orders(1))
        .thenAnswer((_) async => const OrderPage([], ActivityMeta(1, 1)));
    when(() => tickets.list(page: 1)).thenAnswer(
      (_) async => const TicketPage(
        data: [],
        meta: TicketPageMeta(page: 1, totalPages: 1),
      ),
    );
  });

  Future<void> show(
    WidgetTester tester, {
    CreatedOrder? created,
    bool settle = true,
  }) async {
    router = GoRouter(
      initialLocation: '/orders/o1/status',
      routes: [
        GoRoute(
          path: '/orders/:id/status',
          builder: (_, _) => OrderStatusPage(orderId: 'o1', created: created),
        ),
        GoRoute(
          path: '/profile/orders',
          builder: (_, _) => const Scaffold(body: Text('Pedidos')),
        ),
        GoRoute(
          path: '/tickets',
          builder: (_, _) => const Scaffold(body: Text('Ingressos')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(activity),
          ticketsRepositoryProvider.overrideWithValue(tickets),
          authSessionProvider.overrideWithValue(session),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('pendente mostra pagamento apenas com link confirmado', (
    tester,
  ) async {
    when(() => activity.order('o1'))
        .thenAnswer((_) async => order('pending', payment: true));
    await show(tester);
    expect(find.text('Aguardando pagamento'), findsOneWidget);
    expect(find.text('Abrir pagamento'), findsOneWidget);
    expect(find.text('Ver meus ingressos'), findsNothing);
  });

  testWidgets('Voltar em uma confirmação aberta direto mostra os pedidos', (
    tester,
  ) async {
    when(() => activity.order('o1')).thenAnswer((_) async => order('paid'));
    await show(tester);
    expect(find.text('Pedido confirmado'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Pedidos'), findsOneWidget);
  });

  testWidgets(
    'falha na consulta permite retry e só libera ingressos após pago',
    (tester) async {
      var calls = 0;
      when(() => activity.order('o1')).thenAnswer((_) async {
        if (++calls == 1) throw Exception('offline');
        return order('paid');
      });
      await show(tester);
      expect(find.text('Não foi possível atualizar o pedido.'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Pedido confirmado'), findsOneWidget);
      expect(find.text('Ver meus ingressos'), findsOneWidget);
      expect(find.text('Abrir pagamento'), findsNothing);
      verify(() => activity.order('o1')).called(2);
      verify(() => tickets.list(page: 1)).called(1);
    },
  );

  testWidgets('resumo criado não presume pagamento durante consulta', (
    tester,
  ) async {
    final response = Completer<OrderDetails>();
    when(() => activity.order('o1')).thenAnswer((_) => response.future);
    await show(
      tester,
      created: const CreatedOrder('o1', [
        CheckoutPaymentLink('PAY', 'https://payment.example/checkout', 'GET'),
      ], []),
      settle: false,
    );
    expect(find.text('Pedido criado'), findsOneWidget);
    expect(find.text('Pedido confirmado'), findsNothing);
    response.complete(order('pending'));
    await tester.pumpAndSettle();
    expect(find.text('Aguardando pagamento'), findsOneWidget);
  });
}
