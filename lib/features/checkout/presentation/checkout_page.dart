import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:remixicon/remixicon.dart';

import '../../../core/design_system/app_surfaces.dart';
import '../../../core/design_system/corevent_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../profile/presentation/age_policy_page.dart';
import '../data/checkout_dtos.dart';
import 'checkout_view_model.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(checkoutViewModelProvider.notifier).load(widget.eventId);
      }
    });
  }

  Future<void> _submit() async {
    final model = ref.read(checkoutViewModelProvider.notifier);
    final policy = await model.submit();
    if (!mounted) return;
    if (policy != null) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Confirmação de idade'),
          content: SingleChildScrollView(child: Text(policy.description)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Li e aceito'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await model.acceptAndSubmit();
        if (mounted) ref.invalidate(agePolicyStatusProvider);
      }
    }
    if (!mounted) return;
    final order = ref.read(checkoutViewModelProvider).order;
    if (order != null) {
      context.go('/orders/${order.orderId}/status', extra: order);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkoutViewModelProvider);
    final model = ref.read(checkoutViewModelProvider.notifier);
    final working = state.submitting;
    return PopScope(
      canPop: !working,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          shape: const Border(bottom: AppSurfaces.outline),
          title: const Text('Escolher ingressos'),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: working
                ? null
                : () => context.canPop() ? context.pop() : context.go('/home'),
            icon: const Icon(RemixIcons.arrow_left_line),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Expanded(
                  child: state.loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (state.event != null) ...[
                              if (state.event!.isAdultOnly)
                                const AgePolicyNotice(),
                              Text(
                                state.event!.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                DateFormat(
                                  'dd MMM yyyy · HH:mm',
                                  'pt_BR',
                                ).format(state.event!.startDate.toLocal()),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (state.error != null)
                              _Message(state.error!, error: true),
                            if (state.notice != null) _Message(state.notice!),
                            if (state.uncertain) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => context.go('/profile/orders'),
                                child: const Text('Consultar meus pedidos'),
                              ),
                            ] else if (state.error != null &&
                                state.types.isEmpty)
                              TextButton(
                                onPressed: () => model.load(widget.eventId),
                                child: const Text('Tentar novamente'),
                              ),
                            if (state.types.isEmpty && state.error == null)
                              const _Message(
                                'Nenhum ingresso disponível para este evento.',
                              ),
                            for (final type in state.types) ...[
                              _TicketChoice(
                                type: type,
                                quantity: state.quantity(type.id),
                                enabled: !working && !state.uncertain,
                                onChanged: (value) =>
                                    model.setQuantity(type, value),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                ),
                if (!state.loading &&
                    !state.uncertain &&
                    state.types.isNotEmpty)
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      14,
                      20,
                      14 + MediaQuery.paddingOf(context).bottom,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: AppSurfaces.outline),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${state.count} ${state.count == 1 ? 'ingresso' : 'ingressos'}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                _money.format(state.total),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        CoreventButton(
                          label: 'Continuar',
                          busy: working,
                          onPressed: state.count > 0 ? _submit : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketChoice extends StatelessWidget {
  const _TicketChoice({
    required this.type,
    required this.quantity,
    required this.enabled,
    required this.onChanged,
  });
  final CheckoutTicketType type;
  final int quantity;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final available =
        type.availableQuantity > 0 &&
        type.endDate.toLocal().isAfter(DateTime.now()) &&
        !type.startDate.toLocal().isAfter(DateTime.now());
    final max = type.price == 0 ? 1 : type.availableQuantity;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppSurfaces.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            type.name,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            type.price == 0 ? 'Gratuito' : _money.format(type.price),
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            available
                ? '${type.availableQuantity} disponíveis'
                : 'Indisponível',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Diminuir ${type.name}',
                onPressed: enabled && quantity > 0
                    ? () => onChanged(quantity - 1)
                    : null,
                icon: const Icon(RemixIcons.indeterminate_circle_line),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Adicionar ${type.name}',
                onPressed: enabled && available && quantity < max
                    ? () => onChanged(quantity + 1)
                    : null,
                icon: const Icon(RemixIcons.add_circle_line),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: TextStyle(
        color: error ? AppColors.error : AppColors.textSecondary,
      ),
    ),
  );
}
