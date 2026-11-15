import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../core/design_system/corevent_button.dart';
import '../../../core/design_system/icon_label.dart';
import '../../../core/theme/app_colors.dart';
import '../../favorites/presentation/event_favorite_button.dart';
import '../../profile/presentation/age_policy_page.dart';
import '../../ratings/data/rating_dtos.dart';
import '../../ratings/presentation/event_ratings_view_model.dart';
import '../../ratings/presentation/rating_widgets.dart';
import '../data/event_dtos.dart';
import '../data/events_repository.dart';
import '../domain/event_catalog.dart';
import 'event_widgets.dart';

Future<void> showEventPreview(
  BuildContext context,
  EventsRepository repository,
  EventSummary event,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  elevation: 0,
  backgroundColor: AppColors.surface,
  constraints: const BoxConstraints(maxWidth: 720),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _EventPreviewSheet(repository: repository, event: event),
);

class _EventPreviewSheet extends ConsumerStatefulWidget {
  const _EventPreviewSheet({required this.repository, required this.event});

  final EventsRepository repository;
  final EventSummary event;

  @override
  ConsumerState<_EventPreviewSheet> createState() => _EventPreviewSheetState();
}

class _EventPreviewSheetState extends ConsumerState<_EventPreviewSheet> {
  late Future<EventDetail> detail;

  @override
  void initState() {
    super.initState();
    detail = widget.repository.detail(widget.event.id);
  }

  void retry() => setState(() {
    detail = widget.repository.detail(widget.event.id);
  });

  @override
  Widget build(BuildContext context) {
    ref.listen(
      eventRatingsViewModelProvider.select((s) => s.revision),
      (_, _) => retry(),
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .78,
      minChildSize: .45,
      maxChildSize: .95,
      builder: (context, controller) => FutureBuilder<EventDetail>(
        future: detail,
        builder: (context, snapshot) {
          final loaded = snapshot.data;
          final summary = widget.event;
          final title = loaded?.title ?? summary.title;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Prévia do evento',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar prévia',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(RemixIcons.close_line),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    SizedBox(
                      height: 200,
                      child: EventArtwork(
                        url: loaded?.bannerUrl ?? summary.bannerUrl,
                        radius: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _PreviewTag(
                          EventCatalog.categoryLabel(
                            loaded?.category ?? summary.category,
                          ),
                          AppColors.orangeSoft,
                          AppColors.primaryDark,
                        ),
                        _PreviewTag(
                          EventCatalog.locationTypeLabel(
                            loaded?.locationType ?? summary.locationType,
                          ),
                          AppColors.backgroundSecondary,
                          AppColors.textPrimary,
                        ),
                        if (loaded?.isAdultOnly ?? summary.isAdultOnly)
                          const _PreviewTag(
                            '+18',
                            AppColors.pinkSoft,
                            AppColors.pink,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: EventFavoriteButton(
                        eventId: summary.id,
                        withLabel: true,
                      ),
                    ),
                    if (loaded?.isAdultOnly ?? summary.isAdultOnly) ...[
                      const SizedBox(height: 12),
                      const AgePolicyNotice(),
                    ],
                    const SizedBox(height: 12),
                    _PreviewLine(
                      RemixIcons.calendar_event_line,
                      eventDate(
                        context,
                        loaded?.startDate ?? summary.startDate,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PreviewLine(
                      RemixIcons.map_pin_line,
                      eventLocation(
                        loaded?.locationName ?? summary.locationName,
                        loaded?.locationType ?? summary.locationType,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PreviewLine(
                      RemixIcons.user_line,
                      loaded?.organizer.name ?? summary.organizer.name,
                    ),
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) ...[
                      const SizedBox(height: 24),
                      const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ] else if (snapshot.hasError) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Não foi possível carregar a descrição deste evento.',
                        style: TextStyle(color: AppColors.error),
                      ),
                      const SizedBox(height: 8),
                      CoreventTextAction(
                        label: 'Tentar novamente',
                        onPressed: retry,
                      ),
                    ] else if (loaded?.description?.trim().isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Sobre o evento',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loaded!.description!.trim(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    EventRatingSection(
                      event: RatedEvent(
                        eventId: summary.id,
                        eventTitle: title,
                        userRating: 0,
                        averageRating:
                            loaded?.averageRating ?? summary.averageRating,
                        ratingCount: loaded?.ratingCount ?? summary.ratingCount,
                        bannerUrl: loaded?.bannerUrl ?? summary.bannerUrl,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if ((loaded?.endDate ?? summary.endDate).toLocal().isAfter(
                      DateTime.now(),
                    ))
                      CoreventButton(
                        label: 'Escolher ingressos',
                        onPressed: () {
                          final router = GoRouter.of(context);
                          Navigator.of(context).pop();
                          router.push('/events/${summary.id}/checkout');
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewTag extends StatelessWidget {
  const _PreviewTag(this.label, this.background, this.foreground);

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => CoreventIconLabel(
    icon: icon,
    label: label,
    iconColor: AppColors.primary,
    iconSize: 20,
    spacing: 12,
    style: const TextStyle(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
  );
}
