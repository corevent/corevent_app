import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system/app_tokens.dart';
import '../features/auth/presentation/auth_flow_store.dart';
import '../features/auth/presentation/auth_session.dart';
import '../features/auth/presentation/authenticated_page.dart';
import '../features/auth/presentation/forgot_password_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/auth/presentation/reset_password_page.dart';
import '../features/auth/presentation/verification_page.dart';
import '../features/auth/presentation/verification_view_model.dart';
import '../features/checkout/data/checkout_dtos.dart';
import '../features/checkout/presentation/checkout_page.dart';
import '../features/checkout/presentation/checkout_view_model.dart';
import '../features/checkout/presentation/order_status_page.dart';
import '../features/events/domain/event_discovery_filter.dart';
import '../features/explore/presentation/explore_page.dart';
import '../features/explore/presentation/explore_view_model.dart';
import '../features/favorites/presentation/event_favorites_view_model.dart';
import '../features/favorites/presentation/favorites_page.dart';
import '../features/favorites/presentation/favorites_view_model.dart';
import '../features/home/presentation/home_page.dart';
import '../features/home/presentation/home_view_model.dart';
import '../features/profile/presentation/activity_pages.dart';
import '../features/profile/presentation/activity_view_model.dart';
import '../features/profile/presentation/age_policy_page.dart';
import '../features/profile/presentation/avatar_view_model.dart';
import '../features/profile/presentation/profile_details_page.dart';
import '../features/profile/presentation/profile_form_pages.dart';
import '../features/profile/presentation/profile_forms_view_model.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/profile/presentation/profile_view_model.dart';
import '../features/ratings/presentation/event_ratings_view_model.dart';
import '../features/ratings/presentation/ratings_page.dart';
import '../features/tickets/presentation/tickets_page.dart';
import '../features/tickets/presentation/tickets_view_model.dart';
import '../features/welcome/presentation/welcome_page.dart';
import 'authenticated_shell.dart';
import 'debug/design_gallery_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);
  final flow = ref.watch(authFlowStoreProvider);
  void clearPrivateState() {
    if (session.status != SessionStatus.unauthenticated) return;
    ref.invalidate(homeViewModelProvider);
    ref.invalidate(exploreViewModelProvider);
    ref.invalidate(ticketsViewModelProvider);
    ref.invalidate(profileViewModelProvider);
    ref.invalidate(ordersViewModelProvider);
    ref.invalidate(favoritesViewModelProvider);
    ref.invalidate(eventFavoritesViewModelProvider);
    ref.invalidate(eventRatingsViewModelProvider);
    ref.invalidate(ratingsViewModelProvider);
    ref.invalidate(detailsViewModelProvider);
    ref.invalidate(avatarViewModelProvider);
    ref.invalidate(securityViewModelProvider);
    ref.invalidate(checkoutViewModelProvider);
    ref.invalidate(agePolicyStatusProvider);
  }

  session.addListener(clearPrivateState);
  ref.onDispose(() => session.removeListener(clearPrivateState));
  final router = GoRouter(
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.uri.path;
      if (kDebugMode && path == '/design-system') return null;
      final status = session.status;
      const tabs = {'/home', '/explore', '/tickets', '/profile'};
      final protected =
          tabs.contains(path) ||
          path.startsWith('/profile/') ||
          path.startsWith('/events/') ||
          path.startsWith('/orders/');
      if (status == SessionStatus.authenticated &&
          !protected &&
          path != '/loading') {
        return '/home';
      }
      if (protected && status == SessionStatus.unauthenticated) {
        return '/';
      }
      if (protected && status != SessionStatus.authenticated) {
        return '/loading?next=$path';
      }
      if (path == '/loading' && status == SessionStatus.authenticated) {
        final next = state.uri.queryParameters['next'];
        return next != null &&
                (tabs.contains(next) ||
                    next.startsWith('/profile/') ||
                    next.startsWith('/events/') ||
                    next.startsWith('/orders/'))
            ? next
            : '/home';
      }
      if (path == '/loading' && status == SessionStatus.unauthenticated) {
        return '/';
      }
      if (path == '/' && status == SessionStatus.loading) return '/loading';
      if (path == '/verify/register' && flow.registration == null) {
        return '/register';
      }
      if (path == '/verify/reset' && flow.recoveryEmail == null) {
        return '/forgot-password';
      }
      if (path == '/reset-password' &&
          (flow.recoveryEmail == null || flow.recoveryCode == null)) {
        return '/forgot-password';
      }
      return null;
    },
    routes: [
      if (kDebugMode)
        GoRoute(
          path: '/design-system',
          name: 'designSystem',
          builder: (_, _) => const DesignGalleryPage(),
        ),
      GoRoute(
        path: '/',
        name: 'welcome',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const WelcomePage(),
        ),
      ),
      GoRoute(
        path: '/loading',
        name: 'loading',
        builder: (_, _) => const SessionLoadingPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const RegisterPage(),
        ),
      ),
      GoRoute(
        path: '/verify/register',
        name: 'verifyRegister',
        pageBuilder: (context, state) => _animatedPage(
          context,
          state,
          const VerificationPage(mode: VerificationMode.register),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        pageBuilder: (context, state) =>
            _animatedPage(context, state, const ForgotPasswordPage()),
      ),
      GoRoute(
        path: '/verify/reset',
        name: 'verifyReset',
        pageBuilder: (context, state) => _animatedPage(
          context,
          state,
          const VerificationPage(mode: VerificationMode.reset),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        name: 'resetPassword',
        pageBuilder: (context, state) =>
            _animatedPage(context, state, const ResetPasswordPage()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AuthenticatedShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (_, _) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                name: 'explore',
                builder: (_, state) => ExplorePage(
                  discovery: state.uri.queryParameters.isEmpty
                      ? null
                      : EventDiscoveryFilter.fromQuery(
                          state.uri.queryParameters,
                        ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tickets',
                name: 'tickets',
                builder: (_, _) => const TicketsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (_, _) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/profile/details',
        name: 'profileDetails',
        builder: (_, _) => const ProfileDetailsPage(),
      ),
      GoRoute(
        path: '/events/:id/checkout',
        name: 'checkout',
        builder: (_, state) =>
            CheckoutPage(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/orders/:id/status',
        name: 'orderStatus',
        builder: (_, state) => OrderStatusPage(
          orderId: state.pathParameters['id']!,
          created: state.extra is CreatedOrder
              ? state.extra as CreatedOrder
              : null,
        ),
      ),
      GoRoute(
        path: '/profile/security',
        name: 'profileSecurity',
        builder: (_, _) => const ProfileSecurityPage(),
      ),
      GoRoute(
        path: '/profile/age-policy',
        name: 'profileAgePolicy',
        builder: (_, _) => const AgePolicyPage(),
      ),
      GoRoute(
        path: '/profile/orders',
        name: 'profileOrders',
        builder: (_, _) => const ActivityPage(kind: ActivityKind.orders),
      ),
      GoRoute(
        path: '/profile/orders/:id',
        name: 'profileOrderDetail',
        builder: (_, state) => OrderDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/profile/favorites',
        name: 'profileFavorites',
        builder: (_, _) => const FavoritesPage(),
      ),
      GoRoute(
        path: '/profile/ratings',
        name: 'profileRatings',
        builder: (_, _) => const RatingsPage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

CustomTransitionPage<void> _animatedPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: AppMotion.duration(context, AppMotion.standard),
  reverseTransitionDuration: AppMotion.duration(context, AppMotion.standard),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final eased = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.035, 0),
          end: Offset.zero,
        ).animate(eased),
        child: child,
      ),
    );
  },
);
