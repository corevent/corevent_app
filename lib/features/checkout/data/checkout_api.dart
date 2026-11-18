import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import 'checkout_dtos.dart';

part 'checkout_api.g.dart';

@RestApi()
abstract class CheckoutApi {
  factory CheckoutApi(Dio dio, {String? baseUrl}) = _CheckoutApi;

  @GET('/api/events/{eventId}/ticket-types')
  Future<TicketTypePage> ticketTypes(
    @Path('eventId') String eventId,
    @Query('page') int page,
    @Query('limit') int limit,
    @Query('availableOnly') bool availableOnly,
  );

  @POST('/api/events/{eventId}/orders')
  Future<CreatedOrderResponse> createOrder(
    @Path('eventId') String eventId,
    @Body() Map<String, dynamic> body,
  );

  @GET('/api/age-policies/acceptances/check')
  Future<AgeAcceptanceResponse> checkAgeAcceptance();

  @GET('/api/age-policies')
  Future<AgePolicyResponse> agePolicy();

  @POST('/api/age-policies/acceptances')
  Future<void> acceptAgePolicy();

  @DELETE('/api/age-policies/acceptances')
  Future<void> revokeAgePolicy();
}
