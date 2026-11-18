import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_session.dart';
import '../features/checkout/data/checkout_repository.dart';
import '../features/profile/data/avatar_picker.dart';
import 'router.dart';

class CoreventApp extends ConsumerStatefulWidget {
  const CoreventApp({super.key, this.incomingLinks});

  final Stream<Uri>? incomingLinks;

  @override
  ConsumerState<CoreventApp> createState() => _CoreventAppState();
}

class _CoreventAppState extends ConsumerState<CoreventApp> {
  StreamSubscription<Uri>? _links;
  AuthSession? _session;
  bool _pendingOrderReturn = false;
  bool _pendingAvatarRecovery = false;

  @override
  void initState() {
    super.initState();
    _session = ref.read(authSessionProvider);
    _session!.addListener(_resumePendingReturn);
    _session!.addListener(_resumeAvatarRecovery);
    _links = (widget.incomingLinks ?? AppLinks().uriLinkStream).listen(
      _handleLink,
    );
    unawaited(_recoverAvatar());
  }

  Future<void> _recoverAvatar() async {
    try {
      final recovered = await ref.read(avatarPickerProvider).recover();
      if (!mounted || !recovered) return;
      _pendingAvatarRecovery = true;
      _resumeAvatarRecovery();
    } catch (_) {}
  }

  void _resumeAvatarRecovery() {
    if (!_pendingAvatarRecovery || !mounted || _pendingOrderReturn) return;
    if (ref.read(authSessionProvider).status != SessionStatus.authenticated) {
      return;
    }
    _pendingAvatarRecovery = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(routerProvider).go('/profile/details');
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.scheme != 'corevent' || uri.host != 'orders') return;
    _pendingOrderReturn = true;
    await _resumePendingReturn();
  }

  Future<void> _resumePendingReturn() async {
    if (!_pendingOrderReturn || !mounted) return;
    final session = ref.read(authSessionProvider);
    final userId = session.user?.id;
    if (userId == null || session.status != SessionStatus.authenticated) return;
    _pendingOrderReturn = false;
    final orderId = await ref.read(pendingCheckoutStoreProvider).read(userId);
    if (!mounted) return;
    final router = ref.read(routerProvider);
    final destination = orderId == null
        ? '/profile/orders'
        : '/orders/$orderId/status';
    if (orderId != null &&
        router.canPop() &&
        router.state.uri.path == destination) {
      return;
    }
    router.go(destination);
  }

  @override
  void dispose() {
    _links?.cancel();
    _session?.removeListener(_resumePendingReturn);
    _session?.removeListener(_resumeAvatarRecovery);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Corevent',
      theme: AppTheme.light,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
