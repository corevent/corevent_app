import 'dart:async';

import 'package:corevent_mobile_app/app/app.dart';
import 'package:corevent_mobile_app/core/design_system/corevent_step_progress.dart';
import 'package:corevent_mobile_app/core/storage/token_store.dart';
import 'package:corevent_mobile_app/features/auth/data/auth_dtos.dart';
import 'package:corevent_mobile_app/features/auth/data/auth_repository.dart';
import 'package:corevent_mobile_app/features/auth/presentation/auth_session.dart';
import 'package:corevent_mobile_app/features/auth/presentation/authenticated_page.dart';
import 'package:corevent_mobile_app/features/auth/presentation/register_page.dart';
import 'package:corevent_mobile_app/features/auth/presentation/register_view_model.dart';
import 'package:corevent_mobile_app/features/events/data/event_dtos.dart';
import 'package:corevent_mobile_app/features/events/data/events_repository.dart';
import 'package:corevent_mobile_app/features/profile/presentation/profile_page.dart';
import 'package:corevent_mobile_app/features/tickets/data/ticket_dtos.dart';
import 'package:corevent_mobile_app/features/tickets/data/tickets_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:remixicon/remixicon.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockEventsRepository extends Mock implements EventsRepository {}

class MockTicketsRepository extends Mock implements TicketsRepository {}

class MemoryTokenStore extends ChangeNotifier implements TokenStore {
  String? access;
  String? refresh;

  @override
  Future<String?> readAccess() async => access;

  @override
  Future<String?> readRefresh() async => refresh;

  @override
  Future<void> save(String newAccess, String newRefresh) async {
    access = newAccess;
    refresh = newRefresh;
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    notifyListeners();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RegisterRequest(
        name: 'Teste',
        phoneNumber: '',
        avatarUrl: '',
        email: 'a@b.com',
        password: 'Senha1!',
        birthDate: '2000-01-01',
        documentType: 'cpf',
        document: '52998224725',
        verifyEmailCode: '123456',
      ),
    );
  });

  late MockAuthRepository repository;
  late MockEventsRepository eventsRepository;
  late MockTicketsRepository ticketsRepository;
  late AuthSession session;
  late MemoryTokenStore tokens;

  setUp(() {
    repository = MockAuthRepository();
    eventsRepository = MockEventsRepository();
    ticketsRepository = MockTicketsRepository();
    when(() => ticketsRepository.list(page: any(named: 'page'))).thenAnswer(
      (_) async => const TicketPage(
        data: [],
        meta: TicketPageMeta(page: 1, totalPages: 1),
      ),
    );
    when(
      () => eventsRepository.list(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        search: any(named: 'search'),
        category: any(named: 'category'),
      ),
    ).thenAnswer(
      (_) async => const EventPage(
        data: [],
        meta: EventPageMeta(totalPages: 1, page: 1),
      ),
    );
    tokens = MemoryTokenStore();
    session = AuthSession(repository, tokens)
      ..status = SessionStatus.unauthenticated;
  });

  tearDown(() {
    session.dispose();
    tokens.dispose();
  });

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          eventsRepositoryProvider.overrideWithValue(eventsRepository),
          ticketsRepositoryProvider.overrideWithValue(ticketsRepository),
          authSessionProvider.overrideWithValue(session),
        ],
        child: const CoreventApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, String label) async {
    final button = find.widgetWithText(ElevatedButton, label);
    final finder = button.evaluate().isNotEmpty
        ? button.first
        : find.text(label).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  final backButton = find.ancestor(
    of: find.byIcon(RemixIcons.arrow_left_line),
    matching: find.byType(IconButton),
  );

  void expectSubmissionLocked(WidgetTester tester) {
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((field) => field.enabled == false),
      true,
    );
    expect(tester.widget<IconButton>(backButton).onPressed, isNull);
    expect(
      tester
          .widget<PopScope>(
            find.byWidgetPredicate((widget) => widget is PopScope).last,
          )
          .canPop,
      false,
    );
  }

  testWidgets('login valida campos e abre a área autenticada', (tester) async {
    when(() => repository.login('ana@corevent.com', 'Senha1!')).thenAnswer(
      (_) async =>
          const UserProfile(id: '1', name: 'Ana', email: 'ana@corevent.com'),
    );
    await openApp(tester);
    expect(find.textContaining('eventos incríveis'), findsOneWidget);
    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    expect(find.text('Bem-vindo de volta!'), findsOneWidget);
    await tapVisible(tester, 'Entrar');
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'ana@corevent.com');
    await tester.enterText(find.byType(TextField).at(1), 'Senha1!');
    await tapVisible(tester, 'Entrar');
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana!'), findsOneWidget);
  });

  testWidgets('abas preservam navegação e perfil permite sair', (tester) async {
    session.user = const UserProfile(
      id: '1',
      name: 'Ana Silva',
      email: 'ana@corevent.com',
    );
    session.status = SessionStatus.authenticated;
    when(() => repository.logout()).thenAnswer((_) async {});
    await openApp(tester);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Explorar'), findsOneWidget);
    expect(find.text('Ingressos'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();
    expect(find.text('Categorias'), findsOneWidget);
    await tester.tap(find.text('Ingressos'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum ingresso ainda'), findsOneWidget);
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Silva'), findsOneWidget);
    expect(find.text('Membro Corevent'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana!'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir perfil'));
    await tester.pumpAndSettle();
    final logoutButton = find.widgetWithText(OutlinedButton, 'Sair da conta');
    await tester.scrollUntilVisible(
      logoutButton,
      200,
      scrollable: find.descendant(
        of: find.byType(ProfilePage),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(logoutButton.hitTestable(), findsOneWidget);
    await tester.tap(logoutButton);
    await tester.pumpAndSettle();
    expect(find.text('Sair da conta?'), findsOneWidget);
    await tester.tap(find.text('Sair').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('eventos incríveis'), findsOneWidget);
    verify(() => repository.logout()).called(1);
  });

  testWidgets('abas e cabeçalho cabem no celular com fonte em 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    session.user = const UserProfile(
      id: '1',
      name: 'Ana Silva',
      email: 'ana@corevent.com',
    );
    session.status = SessionStatus.authenticated;
    await openApp(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ingressos'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro passa pelos quatro passos e verifica código', (
    tester,
  ) async {
    when(() => repository.sendVerification('ana@corevent.com'))
        .thenAnswer((_) async {});
    when(() => repository.register(any())).thenAnswer((_) async {});
    when(() => repository.login('ana@corevent.com', 'Senha123!')).thenAnswer(
      (_) async =>
          const UserProfile(id: '1', name: 'Ana', email: 'ana@corevent.com'),
    );
    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ana Silva');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.enterText(find.byType(TextField).at(2), '06');
    await tester.enterText(find.byType(TextField).at(3), '1998');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Pessoa Física');
    await tester.pumpAndSettle();
    expect(find.text('Pessoa ou empresa?'), findsOneWidget);
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '52998224725');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'ana@corevent.com');
    await tester.enterText(find.byType(TextField).at(1), 'Senha123!');
    await tester.enterText(find.byType(TextField).at(2), 'Senha123!');
    final draft = ProviderScope.containerOf(
      tester.element(find.byType(RegisterPage)),
    ).read(registerViewModelProvider).draft;
    expect(draft.password, 'Senha123!');
    await tapVisible(tester, 'Finalizar');
    await tester.pumpAndSettle();
    expect(
      find.text('Verifique seu e-mail'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((value) => value.data)
          .join(' | '),
    );
    await tester.enterText(find.byType(TextField).first, '123456');
    await tapVisible(tester, 'Verificar');
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana!'), findsOneWidget);
    verify(() => repository.register(any())).called(1);
  });

  testWidgets('tipo de conta exige seleção e confirma com Próximo', (
    tester,
  ) async {
    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ana Silva');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.enterText(find.byType(TextField).at(2), '06');
    await tester.enterText(find.byType(TextField).at(3), '1998');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    expect(find.text('Selecione o tipo de conta.'), findsOneWidget);
    await tapVisible(tester, 'Pessoa Jurídica');
    await tester.pumpAndSettle();
    expect(find.text('Pessoa ou empresa?'), findsOneWidget);
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    expect(find.text('CNPJ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '04252011000110');
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Pessoa Jurídica');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '04.252.011/0001-10',
    );
  });

  testWidgets('recuperação usa código e redefine senha', (tester) async {
    when(() => repository.sendResetCode('ana@corevent.com'))
        .thenAnswer((_) async {});
    when(
      () =>
          repository.resetPassword('ana@corevent.com', '123456', 'NovaSenha1!'),
    ).thenAnswer((_) async {});
    await openApp(tester);
    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Esqueceu a senha?');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ana@corevent.com');
    await tapVisible(tester, 'Enviar código');
    await tester.pumpAndSettle();
    expect(find.text('Verifique seu e-mail'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '123456');
    await tapVisible(tester, 'Verificar');
    await tester.pumpAndSettle();
    expect(find.text('Redefinir senha'), findsWidgets);
    await tester.enterText(find.byType(TextField).at(0), 'NovaSenha1!');
    await tester.enterText(find.byType(TextField).at(1), 'NovaSenha1!');
    await tapVisible(tester, 'Redefinir senha');
    await tester.pumpAndSettle();
    expect(find.text('Bem-vindo de volta!'), findsOneWidget);
    verify(
      () =>
          repository.resetPassword('ana@corevent.com', '123456', 'NovaSenha1!'),
    ).called(1);
  });

  testWidgets('fonte ampliada mantém botões utilizáveis no celular', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await openApp(tester);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    expect(find.text('Conte-nos sobre você'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro suporta fonte em 200% no celular estreito', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    expect(find.text('Etapa 1 de 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Próximo'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('splash de sessão mostra somente a logo', (tester) async {
    session.status = SessionStatus.loading;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWithValue(session)],
        child: const MaterialApp(home: SessionLoadingPage()),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('cadastro faz fade out antes do fade in ao trocar de etapa', (
    tester,
  ) async {
    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ana Silva');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.enterText(find.byType(TextField).at(2), '06');
    await tester.enterText(find.byType(TextField).at(3), '1998');
    await tapVisible(tester, 'Próximo');
    var sawFadeOut = false;
    var sawFadeIn = false;
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      final oldVisible = find
          .text('Conte-nos sobre você')
          .evaluate()
          .isNotEmpty;
      final newVisible = find.text('Pessoa ou empresa?').evaluate().isNotEmpty;
      final opacity = tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('register-step-fade')),
          )
          .opacity
          .value;
      expect(oldVisible && newVisible, false);
      if (oldVisible && opacity < 0.99) sawFadeOut = true;
      if (newVisible && opacity > 0.01 && opacity < 0.99) {
        sawFadeIn = true;
        expect(sawFadeOut, true);
      }
    }
    expect(sawFadeOut, true);
    expect(sawFadeIn, true);
    await tester.pumpAndSettle();
    expect(find.text('Pessoa ou empresa?'), findsOneWidget);
    expect(find.text('Pessoa Física'), findsOneWidget);
  });

  testWidgets('indicador e botão mantêm a posição nas quatro etapas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    final progressY = tester.getTopLeft(find.byType(CoreventStepProgress)).dy;
    final buttonY = tester
        .getTopLeft(find.widgetWithText(ElevatedButton, 'Próximo'))
        .dy;

    void expectFixed(String label) {
      expect(
        tester.getTopLeft(find.byType(CoreventStepProgress)).dy,
        closeTo(progressY, 1),
      );
      expect(
        tester.getTopLeft(find.widgetWithText(ElevatedButton, label)).dy,
        closeTo(buttonY, 1),
      );
      expect(tester.takeException(), isNull);
    }

    await tester.enterText(find.byType(TextField).first, 'Ana Silva');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.enterText(find.byType(TextField).at(2), '06');
    await tester.enterText(find.byType(TextField).at(3), '1998');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    expectFixed('Próximo');

    await tapVisible(tester, 'Pessoa Física');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    expectFixed('Próximo');

    await tester.enterText(find.byType(TextField).first, '52998224725');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    expectFixed('Finalizar');
    await tester.ensureVisible(find.text('Confirmar senha'));
    await tester.pumpAndSettle();
    final footerY = tester
        .getTopLeft(find.widgetWithText(ElevatedButton, 'Finalizar'))
        .dy;
    expect(
      tester.getBottomLeft(find.text('Confirmar senha')).dy,
      lessThan(footerY),
    );
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('register-scroll')),
        )
        .controller!;
    expect(scroll.offset, greaterThan(0));
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });

  testWidgets('teclado mantém o rodapé visível e formulário rolável', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(ElevatedButton, 'Próximo');
    expect(tester.getBottomLeft(button).dy, lessThan(390));
    expect(
      tester.getTopLeft(find.byType(CoreventStepProgress)).dy,
      lessThan(tester.getTopLeft(button).dy),
    );
    await tester.ensureVisible(find.text('Data de nascimento'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('login bloqueia edição e retorno durante envio', (tester) async {
    final pending = Completer<UserProfile>();
    when(() => repository.login('ana@corevent.com', 'Senha1!'))
        .thenAnswer((_) => pending.future);
    await openApp(tester);
    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'ana@corevent.com');
    await tester.enterText(find.byType(TextField).at(1), 'Senha1!');
    await tapVisible(tester, 'Entrar');
    expectSubmissionLocked(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Bem-vindo de volta!'), findsOneWidget);
    pending.completeError(StateError('Falha de rede'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      true,
    );
    expect(tester.widget<IconButton>(backButton).onPressed, isNotNull);
  });

  testWidgets('Voltar do sistema retorna em login, cadastro e recuperação', (
    tester,
  ) async {
    await openApp(tester);
    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('eventos incríveis'), findsOneWidget);

    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('eventos incríveis'), findsOneWidget);

    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Esqueceu a senha?');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bem-vindo de volta!'), findsOneWidget);
  });

  testWidgets('Voltar do sistema retorna nas etapas e na verificação', (
    tester,
  ) async {
    when(() => repository.sendResetCode('ana@corevent.com'))
        .thenAnswer((_) async {});
    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ana Silva');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.enterText(find.byType(TextField).at(2), '06');
    await tester.enterText(find.byType(TextField).at(3), '1998');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Conte-nos sobre você'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Esqueceu a senha?');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ana@corevent.com');
    await tapVisible(tester, 'Enviar código');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tapVisible(tester, 'Verificar');
    await tester.pumpAndSettle();
    expect(find.text('Redefinir senha'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Verifique seu e-mail'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Recuperar senha'), findsOneWidget);
  });

  testWidgets('recuperação bloqueia campos e retorno durante envio', (
    tester,
  ) async {
    final pending = Completer<void>();
    when(() => repository.sendResetCode('ana@corevent.com'))
        .thenAnswer((_) => pending.future);
    await openApp(tester);
    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Esqueceu a senha?');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ana@corevent.com');
    await tapVisible(tester, 'Enviar código');
    expectSubmissionLocked(tester);
    pending.completeError(StateError('Falha de rede'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      true,
    );
  });

  testWidgets('cadastro e verificação bloqueiam durante requisições', (
    tester,
  ) async {
    final sending = Completer<void>();
    final registering = Completer<void>();
    when(() => repository.sendVerification('ana@corevent.com'))
        .thenAnswer((_) => sending.future);
    when(() => repository.register(any()))
        .thenAnswer((_) => registering.future);
    await openApp(tester);
    await tapVisible(tester, 'Criar conta');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ana Silva');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.enterText(find.byType(TextField).at(2), '06');
    await tester.enterText(find.byType(TextField).at(3), '1998');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Pessoa Física');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '52998224725');
    await tapVisible(tester, 'Próximo');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'ana@corevent.com');
    await tester.enterText(find.byType(TextField).at(1), 'Senha123!');
    await tester.enterText(find.byType(TextField).at(2), 'Senha123!');
    await tapVisible(tester, 'Finalizar');
    expectSubmissionLocked(tester);
    sending.complete();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tapVisible(tester, 'Verificar');
    expectSubmissionLocked(tester);
    registering.completeError(StateError('Código inválido'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      true,
    );
  });

  testWidgets('redefinição bloqueia edição e retorno durante envio', (
    tester,
  ) async {
    final pending = Completer<void>();
    when(() => repository.sendResetCode('ana@corevent.com'))
        .thenAnswer((_) async {});
    when(
      () =>
          repository.resetPassword('ana@corevent.com', '123456', 'NovaSenha1!'),
    ).thenAnswer((_) => pending.future);
    await openApp(tester);
    await tapVisible(tester, 'Já tenho uma conta');
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Esqueceu a senha?');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ana@corevent.com');
    await tapVisible(tester, 'Enviar código');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tapVisible(tester, 'Verificar');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'NovaSenha1!');
    await tester.enterText(find.byType(TextField).at(1), 'NovaSenha1!');
    await tapVisible(tester, 'Redefinir senha');
    expectSubmissionLocked(tester);
    pending.completeError(StateError('Falha de rede'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      true,
    );
  });
}
