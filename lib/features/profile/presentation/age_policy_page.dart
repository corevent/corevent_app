import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_session.dart';
import '../../checkout/data/checkout_dtos.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../events/domain/event_visibility.dart';

final agePolicyStatusProvider =
    FutureProvider.autoDispose<({AgePolicy policy, bool accepted})>((ref) {
      return ref.watch(checkoutRepositoryProvider).agePolicyStatus();
    });

class AgePolicyNotice extends ConsumerWidget {
  const AgePolicyNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(agePolicyStatusProvider);
    return Card(
      color: AppColors.orangeSoft,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Política de idade · +18',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              status.when(
                data: (value) => value.accepted
                    ? 'Você já aceitou a política vigente. Pode consultar ou revogar o aceite nas configurações da conta.'
                    : 'Para continuar com a compra deste evento +18, você precisa ler e aceitar a política de idade. O aceite vale para a política vigente.',
                loading: () => 'Consultando seu aceite da política de idade…',
                error: (_, _) => 'Não foi possível consultar seu aceite. Tente novamente nas configurações da política de idade.',
              ),
            ),
            TextButton(
              onPressed: () async {
                await context.push('/profile/age-policy');
                if (context.mounted) ref.invalidate(agePolicyStatusProvider);
              },
              child: const Text('Gerenciar política de idade'),
            ),
          ],
        ),
      ),
    );
  }
}

class AgePolicyPage extends ConsumerStatefulWidget {
  const AgePolicyPage({super.key});

  @override
  ConsumerState<AgePolicyPage> createState() => _AgePolicyPageState();
}

class _AgePolicyPageState extends ConsumerState<AgePolicyPage> {
  bool busy = false;
  String? error;

  Future<void> change(bool accepted) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          accepted ? 'Aceitar política de idade?' : 'Revogar aceite?',
        ),
        content: Text(
          accepted
              ? 'Confirmo que li e aceito a política de idade exibida nesta tela.'
              : 'Você precisará aceitar novamente a política vigente antes de continuar uma compra de evento +18. Seus pedidos existentes não serão alterados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(accepted ? 'Li e aceito' : 'Revogar aceite'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repository = ref.read(checkoutRepositoryProvider);
      if (accepted) {
        await repository.acceptAgePolicy();
      } else {
        await repository.revokeAgePolicy();
      }
      if (!mounted) return;
      ref.invalidate(agePolicyStatusProvider);
      await ref.read(agePolicyStatusProvider.future);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Não foi possível alterar o aceite. Tente novamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(agePolicyStatusProvider);
    final adult = isAdult(
      ref.watch(authSessionProvider).user?.birthDate,
      DateTime.now(),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Política de idade')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: status.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar a política de idade.'),
                  TextButton(
                    onPressed: () => ref.invalidate(agePolicyStatusProvider),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
            data: (value) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Eventos para maiores de 18 anos',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'O aceite fica associado à sua conta e à política vigente. Você pode revogá-lo aqui. Uma nova política exige um novo aceite.',
                ),
                const SizedBox(height: 20),
                Text('Versão ${value.policy.version}'),
                const SizedBox(height: 12),
                Text(value.policy.description),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aceito a política de idade'),
                  subtitle: Text(
                    value.accepted
                        ? 'Aceite registrado na sua conta'
                        : 'Aceite pendente',
                  ),
                  value: value.accepted,
                  onChanged: busy || (!adult && !value.accepted)
                      ? null
                      : change,
                ),
                if (!adult && !value.accepted)
                  const Text(
                    'É necessário ter 18 anos para aceitar esta política.',
                  ),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.error)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
