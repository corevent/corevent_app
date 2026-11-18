import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:remixicon/remixicon.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design_system/app_surfaces.dart';
import '../../../core/design_system/corevent_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_session.dart';
import '../../profile/data/activity_dtos.dart';
import '../../profile/data/activity_repository.dart';
import '../../profile/presentation/activity_view_model.dart';
import '../../tickets/presentation/tickets_view_model.dart';
import '../data/checkout_dtos.dart';
import '../data/checkout_repository.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

class OrderStatusPage extends ConsumerStatefulWidget {
  const OrderStatusPage({super.key, required this.orderId, this.created});
  final String orderId;
  final CreatedOrder? created;

  @override
  ConsumerState<OrderStatusPage> createState() => _OrderStatusPageState();
}

class _OrderStatusPageState extends ConsumerState<OrderStatusPage>
    with WidgetsBindingObserver {
  OrderDetails? _order;
  String? _error;
  bool _loading = true;
  bool _opening = false;
  Timer? _timer;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_order?.status.toLowerCase() == 'pending' && !_loading) {
        if (_pollCount >= 10) {
          _timer?.cancel();
          return;
        }
        _pollCount++;
        _refresh(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(silent: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted || _loading && _order != null) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final order = await ref
          .read(activityRepositoryProvider)
          .order(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
        _error = null;
      });
      if (order.status.toLowerCase() != 'pending') {
        final userId = ref.read(authSessionProvider).user?.id;
        if (userId != null) {
          try {
            final store = ref.read(pendingCheckoutStoreProvider);
            if (await store.read(userId) == widget.orderId) {
              await store.clear(userId);
            }
          } catch (_) {}
        }
        if (!mounted) return;
        await ref.read(ordersViewModelProvider.notifier).load();
        if (!mounted) return;
        if (order.status.toLowerCase() == 'paid') {
          await ref.read(ticketsViewModelProvider.notifier).refresh();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível atualizar o pedido.';
        });
      }
    }
  }

  Future<void> _openPayment(Uri url) async {
    setState(() => _opening = true);
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(
          () => _error = 'Não foi possível abrir o pagamento. Tente novamente.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível abrir o pagamento. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = ModalRoute.canPopOf(context) ?? false;
    final order = _order;
    final status = order?.status.toLowerCase();
    final payment =
        order?.checkout?.checkoutLinks
            .where(
              (link) =>
                  link.rel.toUpperCase() == 'PAY' &&
                  link.method.toUpperCase() == 'GET',
            )
            .map((link) => Uri.tryParse(link.href))
            .whereType<Uri>()
            .where((url) => url.scheme == 'https')
            .firstOrNull ??
        widget.created?.checkoutLinks
            .where(
              (link) =>
                  link.rel.toUpperCase() == 'PAY' &&
                  link.method.toUpperCase() == 'GET',
            )
            .map((link) => Uri.tryParse(link.href))
            .whereType<Uri>()
            .where((url) => url.scheme == 'https')
            .firstOrNull;
    final page = Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        shape: const Border(bottom: AppSurfaces.outline),
        title: const Text('Seu pedido'),
        leading: IconButton(
          tooltip: canGoBack ? 'Voltar' : 'Voltar aos pedidos',
          onPressed: canGoBack
              ? () => context.pop()
              : () => context.go('/profile/orders'),
          icon: const Icon(RemixIcons.arrow_left_line),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                if (_loading && order == null)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                if (order == null && widget.created != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Pedido criado',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pedido ${widget.orderId}. Consulte o status antes de acessar os ingressos.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (payment != null) ...[
                    const SizedBox(height: 20),
                    CoreventButton(
                      label: 'Abrir pagamento',
                      busy: _opening,
                      onPressed: () => _openPayment(payment),
                    ),
                  ],
                ],
                if (order != null) ...[
                  Icon(
                    status == 'paid'
                        ? RemixIcons.checkbox_circle_line
                        : status == 'pending'
                        ? RemixIcons.time_line
                        : RemixIcons.close_circle_line,
                    size: 48,
                    color: status == 'paid'
                        ? AppColors.success
                        : status == 'pending'
                        ? AppColors.primary
                        : AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    status == 'paid'
                        ? 'Pedido confirmado'
                        : status == 'pending'
                        ? 'Aguardando pagamento'
                        : 'Pedido cancelado',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status == 'pending'
                        ? 'Se você já pagou, a confirmação pode levar alguns instantes. Atualize para consultar o status.'
                        : status == 'paid'
                        ? 'Seus ingressos estão disponíveis na aba Ingressos.'
                        : 'Consulte seus pedidos para acompanhar esta compra.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: AppSurfaces.cardDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pedido ${order.id}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total: ${_money.format(order.totalAmount)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (status == 'paid')
                    CoreventButton(
                      label: 'Ver meus ingressos',
                      onPressed: () => context.go('/tickets'),
                    ),
                  if (status == 'pending' && payment != null) ...[
                    CoreventButton(
                      label: 'Abrir pagamento',
                      busy: _opening,
                      onPressed: () => _openPayment(payment),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (status == 'pending' && payment == null)
                    const Text(
                      'O link de pagamento está indisponível. Consulte novamente em instantes.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                if (order == null && !_loading)
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Tentar novamente'),
                  ),
                if (order != null && status == 'pending') ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading ? null : _refresh,
                    child: Text(_loading ? 'Atualizando…' : 'Atualizar status'),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/profile/orders'),
                  child: const Text('Ver todos os pedidos'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canGoBack) context.go('/profile/orders');
      },
      child: page,
    );
  }
}
