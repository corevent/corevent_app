import 'dart:async';

import 'package:corevent_mobile_app/app/app.dart';
import 'package:corevent_mobile_app/app/router.dart';
import 'package:corevent_mobile_app/core/storage/token_store.dart';
import 'package:corevent_mobile_app/features/auth/data/auth_dtos.dart';
import 'package:corevent_mobile_app/features/auth/data/auth_repository.dart';
import 'package:corevent_mobile_app/features/auth/presentation/auth_session.dart';
import 'package:corevent_mobile_app/features/checkout/data/checkout_repository.dart';
import 'package:corevent_mobile_app/features/profile/data/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockPendingCheckoutStore extends Mock implements PendingCheckoutStore {}

class MockAvatarPicker extends Mock implements AvatarPicker {}

class ControlledSession extends AuthSession {
  ControlledSession(super.repository, super.tokens);

  void authenticate() {
    user = const UserProfile(id: 'u1', name: 'Ana', email: 'ana@test.invalid');
    status = SessionStatus.authenticated;
    notifyListeners();
  }
}

void main() {
  late StreamController<Uri> links;
  late TokenStore tokens;
  late ControlledSession session;
  late MockPendingCheckoutStore pending;
  late MockAvatarPicker avatar;
  late GoRouter router;

  setUp(() {
    links = StreamController<Uri>.broadcast();
    tokens = TokenStore(const FlutterSecureStorage());
    session = ControlledSession(MockAuthRepository(), tokens)
      ..status = SessionStatus.unauthenticated;
    pending = MockPendingCheckoutStore();
    avatar = MockAvatarPicker();
    when(() => avatar.recover()).thenAnswer((_) async => false);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Início')),
        ),
        GoRoute(
          path: '/profile/orders',
          builder: (_, _) => const Scaffold(body: Text('Pedidos')),
        ),
        GoRoute(
          path: '/profile/details',
          builder: (_, _) => const Scaffold(body: Text('Dados pessoais')),
        ),
        GoRoute(
          path: '/orders/:id/status',
          builder: (_, state) =>
              Scaffold(body: Text('Pedido ${state.pathParameters['id']}')),
        ),
      ],
    );
  });

  tearDown(() async {
    await links.close();
    router.dispose();
    session.dispose();
    tokens.dispose();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          pendingCheckoutStoreProvider.overrideWithValue(pending),
          avatarPickerProvider.overrideWithValue(avatar),
          routerProvider.overrideWithValue(router),
        ],
        child: CoreventApp(incomingLinks: links.stream),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('retorno do pagamento abre o pedido pendente', (tester) async {
    session.authenticate();
    when(() => pending.read('u1')).thenAnswer((_) async => 'order-1');
    await show(tester);
    links.add(Uri.parse('corevent://orders'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido order-1'), findsOneWidget);
    verify(() => pending.read('u1')).called(1);
  });

  testWidgets('retorno do pagamento preserva o histórico do pedido aberto', (
    tester,
  ) async {
    session.authenticate();
    when(() => pending.read('u1')).thenAnswer((_) async => 'order-1');
    await show(tester);
    unawaited(router.push('/orders/order-1/status'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido order-1'), findsOneWidget);

    links.add(Uri.parse('corevent://orders'));
    await tester.pumpAndSettle();
    verify(() => pending.read('u1')).called(1);
    expect(find.text('Pedido order-1'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Início'), findsOneWidget);
  });

  testWidgets('retorno sem pedido pendente abre a lista', (tester) async {
    session.authenticate();
    when(() => pending.read('u1')).thenAnswer((_) async => null);
    await show(tester);
    links.add(Uri.parse('corevent://orders'));
    await tester.pumpAndSettle();
    expect(find.text('Pedidos'), findsOneWidget);
  });

  testWidgets('link de outro destino não consulta pedidos', (tester) async {
    session.authenticate();
    await show(tester);
    links.add(Uri.parse('https://example.invalid/orders'));
    await tester.pumpAndSettle();
    expect(find.text('Início'), findsOneWidget);
    verifyNever(() => pending.read(any()));
  });

  testWidgets('retorno recebido antes do login espera a sessão', (
    tester,
  ) async {
    when(() => pending.read('u1')).thenAnswer((_) async => 'order-2');
    await show(tester);
    links.add(Uri.parse('corevent://orders'));
    await tester.pumpAndSettle();
    expect(find.text('Início'), findsOneWidget);
    verifyNever(() => pending.read(any()));
    session.authenticate();
    await tester.pumpAndSettle();
    expect(find.text('Pedido order-2'), findsOneWidget);
  });

  testWidgets('foto recuperada espera login e abre dados pessoais', (
    tester,
  ) async {
    final recovered = Completer<bool>();
    when(() => avatar.recover()).thenAnswer((_) => recovered.future);
    await show(tester);
    expect(find.text('Início'), findsOneWidget);
    await tester.runAsync(() async {
      recovered.complete(true);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();
    session.authenticate();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile/details');
    expect(find.text('Dados pessoais'), findsOneWidget);
    verify(() => avatar.recover()).called(1);
  });
}
