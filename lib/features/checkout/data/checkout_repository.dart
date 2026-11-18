import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../../auth/data/auth_providers.dart';
import '../../events/data/event_dtos.dart';
import '../../events/data/events_repository.dart';
import 'checkout_api.dart';
import 'checkout_dtos.dart';

class CheckoutCatalog {
  const CheckoutCatalog(this.event, this.types);
  final EventDetail event;
  final List<CheckoutTicketType> types;
}

class CheckoutRepository {
  const CheckoutRepository(this.api, this.events);
  final CheckoutApi api;
  final EventsRepository events;

  Future<CheckoutCatalog> catalog(String eventId) async {
    final event = await events.detail(eventId);
    final types = <CheckoutTicketType>[];
    var page = 1;
    while (true) {
      final result = await api.ticketTypes(eventId, page, 50, true);
      types.addAll(result.data);
      if (page >= result.meta.totalPages) break;
      page++;
    }
    final unique = <String, CheckoutTicketType>{
      for (final type in types) type.id: type,
    };
    return CheckoutCatalog(event, unique.values.toList());
  }

  Future<CreatedOrder> create(
    String eventId,
    Map<String, int> quantities,
  ) async {
    final items = quantities.entries
        .where((entry) => entry.value > 0)
        .map((entry) => {'ticketTypeId': entry.key, 'quantity': entry.value})
        .toList();
    return (await api.createOrder(eventId, {'items': items})).data;
  }

  Future<AgePolicy?> requiredAgePolicy() async {
    final accepted = (await api.checkAgeAcceptance()).data.userHasAccepted;
    return accepted ? null : (await api.agePolicy()).data;
  }

  Future<void> acceptAgePolicy() => api.acceptAgePolicy();

  Future<({AgePolicy policy, bool accepted})> agePolicyStatus() async {
    final policy = (await api.agePolicy()).data;
    final accepted = (await api.checkAgeAcceptance()).data.userHasAccepted;
    return (policy: policy, accepted: accepted);
  }

  Future<void> revokeAgePolicy() => api.revokeAgePolicy();
}

class PendingCheckoutStore {
  const PendingCheckoutStore(this.ref);
  final Ref ref;
  static const _prefix = 'pending_checkout_';

  Future<void> save(String userId, String orderId) async {
    final prefs = await ref.read(preferencesProvider.future);
    await prefs.setString('$_prefix$userId', orderId);
  }

  Future<String?> read(String userId) async {
    final prefs = await ref.read(preferencesProvider.future);
    return prefs.getString('$_prefix$userId');
  }

  Future<void> clear(String userId) async {
    final prefs = await ref.read(preferencesProvider.future);
    await prefs.remove('$_prefix$userId');
  }
}

final checkoutApiProvider = Provider<CheckoutApi>(
  (ref) => CheckoutApi(ref.watch(authorizedDioProvider)),
);
final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => CheckoutRepository(
    ref.watch(checkoutApiProvider),
    ref.watch(eventsRepositoryProvider),
  ),
);
final pendingCheckoutStoreProvider = Provider<PendingCheckoutStore>(
  (ref) => PendingCheckoutStore(ref),
);
