import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import '../../domain/file_item.dart';
import '../../domain/sensitive_rating.dart';
import '../home_tab.dart';
import '../labels.dart';
import '../scan/scan_view_model.dart';
import '../settings/settings_controller.dart';
import 'sensitive_controller.dart';

/// Blurs [child] when [item] was flagged and the user has not revealed it.
/// [compact] is for list thumbnails: a small icon instead of a Show button.
class SensitiveBlur extends ConsumerWidget {
  const SensitiveBlur({super.key, required this.item, required this.child, this.compact = false});

  final FileItem item;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagged = item.sensitive?.flagged ?? false;
    final blur = ref.watch(settingsProvider.select((s) => s.blurSensitive));
    final hidden = blur && flagged && !ref.watch(revealedProvider).contains(item.id);
    if (!hidden) return child;
    final colors = context.colors;
    final sigma = compact ? 8.0 : 28.0;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ClipRect(
          child: IgnorePointer(
            child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: colors.scrim.withValues(alpha: compact ? 0.15 : 0.35),
            child: Center(
              child: compact
                  ? const Icon(Icons.visibility_off_rounded, size: 18, color: Colors.white)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.visibility_off_rounded, color: Colors.white, size: 32),
                      const UiGap(UiSpace.xs),
                      Text(
                        '${item.sensitive!.level.label} content',
                        style: context.text.titleSmall?.copyWith(color: Colors.white),
                      ),
                      const UiGap(UiSpace.sm),
                      UiButton('Show',
                          icon: Icons.visibility_rounded,
                          size: UiSize.sm,
                          variant: UiButtonVariant.secondary,
                          onPressed: () => reveal(ref, item.id)),
                    ]),
            ),
          ),
        ),
      ],
    );
  }

  static void reveal(WidgetRef ref, String id) => ref.read(revealedProvider.notifier).update((s) => {...s, id});
}

/// Detail-sheet section: level, scores and what they mean.
class SensitiveSection extends StatelessWidget {
  const SensitiveSection({super.key, required this.rating});

  final SensitiveRating rating;

  @override
  Widget build(BuildContext context) {
    String pct(double v) => '${(v * 100).round()} %';
    return UiSection(
      title: 'Content check',
      subtitle: 'On-device model; a flag for review, not proof.',
      child: UiKeyValueList([
        UiKeyValue.custom('Result', child: UiStatusPill(rating.level.label, status: rating.level.status, dot: true)),
        UiKeyValue('Explicit score', pct(rating.explicit)),
        UiKeyValue('Suggestive score', pct(rating.suggestive)),
        if (rating.frames > 1) UiKeyValue('Frames checked', '${rating.frames} (highest score counts)'),
      ]),
    );
  }
}

/// Progress while the check runs, then a summary. Empty when idle.
class SensitiveCheckCard extends ConsumerWidget {
  const SensitiveCheckCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sensitiveCheckProvider);
    if (!s.running && !s.finished) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: UiSpace.md), child: _body(context, ref, s));
  }

  Widget _body(BuildContext context, WidgetRef ref, SensitiveCheckState s) {
    final c = ref.read(sensitiveCheckProvider.notifier);

    if (s.running) {
      return UiCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const UiIconBox(Icons.shield_moon_rounded, size: 36),
            const UiGap(UiSpace.md),
            Expanded(child: Text('Checking photos and videos…', style: context.text.titleMedium)),
            if (s.paused)
              const UiStatusPill('Paused', key: ValueKey('sens-paused'), status: UiStatus.warning)
            else
              const UiStatusPill('On device', key: ValueKey('sens-running'), status: UiStatus.accent, pulse: true),
          ]),
          const UiGap(UiSpace.md),
          UiProgressBar(s.fraction, showPercent: true, height: 8),
          const UiGap(UiSpace.sm),
          Text(
            '${UiFormat.compact(s.checked)} / ${UiFormat.compact(s.total)} checked · '
            '${UiFormat.compact(s.flagged)} flagged',
            style: context.text.bodySmall,
          ),
          const UiGap(UiSpace.md),
          Row(children: [
            Expanded(
              child: UiButton(s.paused ? 'Resume' : 'Pause',
                  icon: s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  variant: UiButtonVariant.secondary,
                  onPressed: s.paused ? c.resume : c.pause),
            ),
            const UiGap(UiSpace.sm),
            Expanded(
              child: UiButton('Stop', icon: Icons.stop_rounded, variant: UiButtonVariant.danger, onPressed: c.cancel),
            ),
          ]),
        ]),
      );
    }

    if (s.error != null) {
      return UiAlert(s.error!, title: 'Content check failed', status: UiStatus.danger, onClose: c.dismiss);
    }
    final message = s.total == 0
        ? 'Every photo and video in these results has already been checked.'
        : '${s.cancelled ? 'Stopped after' : 'Checked'} ${UiFormat.compact(s.checked)} of '
            '${UiFormat.compact(s.total)}. ${UiFormat.compact(s.flagged)} flagged for review'
            '${s.skipped > 0 ? ', ${UiFormat.compact(s.skipped)} could not be decoded' : ''}. '
            'Flagged thumbnails are blurred until you tap Show.';
    return UiAlert(
      message,
      title: s.cancelled ? 'Content check stopped' : 'Content check done',
      status: s.flagged > 0 ? UiStatus.warning : UiStatus.success,
      icon: Icons.shield_moon_rounded,
      onClose: c.dismiss,
      action: s.flagged > 0
          ? UiButton('Show in results', size: UiSize.sm, variant: UiButtonVariant.outline, onPressed: () {
              final f = ref.read(resultFilterProvider.notifier);
              f.state = f.state.copyWith(view: ResultView.sensitive);
              ref.read(homeTabProvider.notifier).state = HomeTab.home;
            })
          : null,
    );
  }
}
