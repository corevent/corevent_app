import 'package:corevent_mobile_app/features/auth/data/auth_dtos.dart';
import 'package:corevent_mobile_app/features/auth/presentation/auth_session.dart';
import 'package:corevent_mobile_app/features/checkout/data/checkout_dtos.dart';
import 'package:corevent_mobile_app/features/checkout/data/checkout_repository.dart';
import 'package:corevent_mobile_app/features/profile/presentation/age_policy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepository extends Mock implements CheckoutRepository {}

class MockSession extends Mock implements AuthSession {}

void main() {
  late MockRepository repository;
  late MockSession session;
  late bool accepted;
  const policy = AgePolicy('p1', 'Termos para eventos +18', 1);

  setUp(() {
    repository = MockRepository();
    session = MockSession();
    accepted = false;
    when(() => session.user).thenReturn(
      const UserProfile(
        id: 'u1',
        name: 'Ana',
        email: 'ana@example.com',
        birthDate: '2000-01-01',
      ),
    );
    when(() => repository.agePolicyStatus())
        .thenAnswer((_) async => (policy: policy, accepted: accepted));
    when(() => repository.acceptAgePolicy()).thenAnswer((_) async {
      accepted = true;
    });
    when(() => repository.revokeAgePolicy()).thenAnswer((_) async {
      accepted = false;
    });
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          checkoutRepositoryProvider.overrideWithValue(repository),
          authSessionProvider.overrideWithValue(session),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('aviso distingue aceite pendente de aceite já registrado', (
    tester,
  ) async {
    await show(tester, const AgePolicyNotice());
    expect(find.textContaining('você precisa ler e aceitar'), findsOneWidget);
    expect(find.text('Gerenciar política de idade'), findsOneWidget);
  });

  testWidgets('mostra aceite existente ao visitar evento +18', (tester) async {
    accepted = true;
    await show(tester, const AgePolicyNotice());
    expect(find.textContaining('Você já aceitou'), findsOneWidget);
  });

  testWidgets('aceita, revoga e permite aceitar novamente na conta', (
    tester,
  ) async {
    await show(tester, const AgePolicyPage());
    expect(find.text(policy.description), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Li e aceito'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revogar aceite'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Li e aceito'));
    await tester.pumpAndSettle();
    verify(() => repository.acceptAgePolicy()).called(2);
    verify(() => repository.revokeAgePolicy()).called(1);
  });

  testWidgets('cancelar não altera o aceite na conta', (tester) async {
    accepted = true;
    await show(tester, const AgePolicyPage());
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    verifyNever(() => repository.revokeAgePolicy());
  });

  testWidgets('falha ao revogar mantém o aceite e informa erro', (
    tester,
  ) async {
    accepted = true;
    when(() => repository.revokeAgePolicy()).thenThrow(Exception('offline'));
    await show(tester, const AgePolicyPage());
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revogar aceite'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.textContaining('Não foi possível alterar'), findsOneWidget);
  });
}
