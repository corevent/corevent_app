import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../core/design_system/app_dialog_styles.dart';
import '../../../core/design_system/app_surfaces.dart';
import '../../../core/design_system/error_toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_session.dart';
import '../domain/membership.dart';
import 'profile_view_model.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (ref.read(profileViewModelProvider).busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleTextStyle: AppDialogStyles.title,
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você precisará entrar novamente para acessar seus ingressos.',
        ),
        actions: [
          TextButton(
            style: AppDialogStyles.action,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: AppDialogStyles.destructiveAction,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(profileViewModelProvider.notifier).logout();
    }
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    await ref.read(profileViewModelProvider.notifier).refresh();
    if (!context.mounted) return;
    final error = ref.read(profileViewModelProvider).error;
    if (error != null) showErrorToast(context, error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final busy = ref.watch(profileViewModelProvider).busy;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _content(context, ref, busy),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, bool busy) {
    final user = ref.read(authSessionProvider).user;
    final name = user?.name.trim() ?? '';
    final initials = name.isEmpty
        ? 'C'
        : name
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part.characters.first.toUpperCase())
              .join();
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: AppSurfaces.outline),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 27,
                        backgroundColor: AppColors.orangeSoft,
                        foregroundImage: user?.avatarUrl?.isNotEmpty == true
                            ? NetworkImage(user!.avatarUrl!)
                            : null,
                        onForegroundImageError:
                            user?.avatarUrl?.isNotEmpty == true
                            ? (_, _) {}
                            : null,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name.isEmpty ? 'Sua conta' : name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              membershipLabel(user?.createdAt, DateTime.now()),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              elevation: 0,
              onRefresh: () => _refresh(context, ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _Group('Minha atividade', [
                    _RowData(
                      RemixIcons.receipt_line,
                      'Pedidos',
                      'Acompanhe suas compras e pagamentos',
                      '/profile/orders',
                    ),
                    _RowData(
                      RemixIcons.heart_line,
                      'Favoritos',
                      'Eventos que você salvou',
                      '/profile/favorites',
                    ),
                    _RowData(
                      RemixIcons.star_line,
                      'Avaliações',
                      'Suas notas sobre eventos',
                      '/profile/ratings',
                    ),
                  ]),
                  _Group('Minha conta', [
                    _RowData(
                      RemixIcons.shield_check_line,
                      'Política de idade',
                      'Consulte, aceite ou revogue a política para eventos +18',
                      '/profile/age-policy',
                    ),
                    _RowData(
                      RemixIcons.user_line,
                      'Dados pessoais',
                      null,
                      '/profile/details',
                    ),
                    _RowData(
                      RemixIcons.lock_line,
                      'Segurança',
                      'Altere sua senha',
                      '/profile/security',
                    ),
                  ]),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _logout(context, ref),
                            icon: const Icon(RemixIcons.logout_box_r_line),
                            label: Text(busy ? 'Aguarde…' : 'Sair da conta'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryDark,
                              side: const BorderSide(
                                color: AppColors.backgroundSecondary,
                              ),
                              minimumSize: const Size.fromHeight(52),
                              textStyle: const TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowData {
  const _RowData(this.icon, this.title, this.description, this.route);
  final IconData icon;
  final String title;
  final String? description;
  final String route;
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String title;
  final List<_RowData> rows;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: AppColors.surface,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: AppSurfaces.cardShape,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        indent: 64,
                        color: AppColors.backgroundSecondary,
                      ),
                    ListTile(
                      onTap: () => context.push(rows[i].route),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      leading: Icon(rows[i].icon, color: AppColors.primary),
                      title: Text(
                        rows[i].title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: rows[i].description == null
                          ? null
                          : Text(rows[i].description!),
                      trailing: const Icon(
                        RemixIcons.arrow_right_s_line,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
