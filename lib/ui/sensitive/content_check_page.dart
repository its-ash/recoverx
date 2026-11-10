import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import '../../core/sensitive/sensitive_checker.dart';
import '../../domain/file_item.dart';
import '../../domain/sensitive_rating.dart';
import '../home_tab.dart';
import '../results/file_detail_sheet.dart';
import '../results/result_tile.dart';
import '../scan/scan_view_model.dart';
import 'sensitive_controller.dart';
import 'sensitive_widgets.dart';

/// "Content check" tab: start the on-device check, watch its progress, and
/// review what it flagged.
class ContentCheckPage extends ConsumerStatefulWidget {
  const ContentCheckPage({super.key});

  @override
  ConsumerState<ContentCheckPage> createState() => _ContentCheckPageState();
}

class _ContentCheckPageState extends ConsumerState<ContentCheckPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);
    final check = ref.watch(sensitiveCheckProvider);
    final selection = ref.watch(selectionProvider);

    final eligible = scan.items.where(SensitiveChecker.eligible).toList();
    final checked = eligible.where((i) => i.sensitive != null).length;
    final pending = eligible.length - checked;
    final flagged = scan.items.where((i) => i.sensitive?.flagged ?? false).toList()
      ..sort((a, b) {
        final byLevel = b.sensitive!.level.index.compareTo(a.sensitive!.level.index);
        return byLevel != 0 ? byLevel : b.sensitive!.explicit.compareTo(a.sensitive!.explicit);
      });
    final explicit = flagged.where((i) => i.sensitive!.level == SensitiveLevel.explicit).length;

    return UiScaffold(
      padding: EdgeInsets.zero,
      appBar: const UiAppBar(title: 'Content check', subtitle: 'On-device sensitive-content review'),
      body: Scrollbar(
        controller: _scroll,
        interactive: true,
        thickness: 8,
        radius: const Radius.circular(UiRadius.full),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(UiSpace.page, UiSpace.lg, UiSpace.page, 0),
              sliver: SliverList.list(children: [
                if (scan.items.isEmpty)
                  UiEmptyState(
                    icon: Icons.shield_moon_rounded,
                    title: 'No results to check',
                    message: 'Run a scan first, then check its photos and videos here.',
                    action: UiButton('Go to Home',
                        variant: UiButtonVariant.secondary,
                        onPressed: () => ref.read(homeTabProvider.notifier).state = HomeTab.home),
                  )
                else ...[
                  if (!check.running)
                    _StartCard(
                      pending: pending,
                      scanning: scan.isScanning,
                      onStart: ref.read(sensitiveCheckProvider.notifier).start,
                    ),
                  const SensitiveCheckCard(),
                  const UiGap(UiSpace.lg),
                  Row(children: [
                    Expanded(child: UiStatCard(label: 'Checked', value: UiFormat.compact(checked))),
                    const UiGap(UiSpace.sm),
                    Expanded(child: UiStatCard(label: 'Explicit', value: UiFormat.compact(explicit))),
                    const UiGap(UiSpace.sm),
                    Expanded(
                        child: UiStatCard(label: 'Suggestive', value: UiFormat.compact(flagged.length - explicit))),
                  ]),
                  const UiGap(UiSpace.lg),
                  UiSectionHeader('Flagged for review (${UiFormat.compact(flagged.length)})',
                      subtitle: 'Most explicit first. Tap to open; blurred until you tap Show.'),
                ],
              ]),
            ),
            if (scan.items.isNotEmpty && flagged.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(UiSpace.xl),
                  child: UiEmptyState(
                    compact: true,
                    icon: Icons.verified_user_rounded,
                    title: checked == 0 ? 'Not checked yet' : 'Nothing flagged',
                    message: checked == 0
                        ? 'Start the check to review photos and videos.'
                        : 'No checked item is above the Sensitivity limits (Settings).',
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: flagged.length,
              itemBuilder: (context, i) {
                final FileItem item = flagged[i];
                return ResultTile(
                  key: ValueKey(item.id),
                  item: item,
                  selected: selection.contains(item.id),
                  onTap: () => showFileDetail(context, item),
                  onToggle: () => ref.read(selectionProvider.notifier).toggle(item.id),
                );
              },
            ),
            const SliverToBoxAdapter(child: UiGap(UiSpace.xxl)),
          ],
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.pending, required this.scanning, required this.onStart});

  final int pending;
  final bool scanning;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const UiIconBox(Icons.shield_moon_rounded, size: 40),
          const UiGap(UiSpace.md),
          Expanded(child: Text('Check photos and videos', style: context.text.titleLarge)),
        ]),
        const UiGap(UiSpace.sm),
        Text(
          pending == 0
              ? 'Every photo and video in these results has been checked.'
              : '${UiFormat.compact(pending)} not checked yet. An NSFW model runs on this phone; '
                  'files are only read and nothing is uploaded. Flagged items are blurred until '
                  'you tap Show.',
          style: context.text.bodyMedium?.copyWith(color: context.colors.textMuted),
        ),
        const UiGap(UiSpace.md),
        const UiAlert(
          'It flags items for review and makes mistakes (swimwear, skin tones, medical photos). '
          'It is not a CSAM detector.',
          status: UiStatus.info,
        ),
        const UiGap(UiSpace.md),
        UiButton(
          scanning ? 'Wait for the scan to finish' : 'Start check',
          icon: Icons.play_arrow_rounded,
          size: UiSize.lg,
          expand: true,
          onPressed: scanning || pending == 0 ? null : onStart,
        ),
      ]),
    );
  }
}
