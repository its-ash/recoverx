import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import '../core/permissions/permission_handler.dart';
import '../core/scanner/scan_models.dart';
import '../domain/file_signature.dart';
import 'export/export_sheet.dart';
import 'labels.dart';
import 'results/file_detail_sheet.dart';
import 'results/result_tile.dart';
import 'scan/scan_radar.dart';
import 'scan/scan_view_model.dart';
import 'home_tab.dart';
import 'settings/settings_controller.dart';
import 'share/browse_controller.dart';

/// Home screen: scan controls, live progress, filters and results.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);
    final browse = ref.watch(browseServerProvider);
    final items = ref.watch(filteredItemsProvider);
    final selection = ref.watch(selectionProvider);
    final permission = ref.watch(permissionStateProvider);
    final hasResults = scan.items.isNotEmpty;

    return UiScaffold(
      padding: EdgeInsets.zero,
      appBar: const UiAppBar(title: 'RecoverX'),
      bottomBar: selection.isEmpty
          ? null
          : UiBottomBar(children: [
              UiButton('Clear (${selection.length})',
                  variant: UiButtonVariant.secondary, onPressed: ref.read(selectionProvider.notifier).clear),
              UiButton('Export',
                  icon: Icons.file_download_rounded,
                  onPressed: scan.isScanning ? null : () => showExportSheet(context)),
            ]),
      // Draggable thumb: jump through thousands of results while the list
      // still builds only the rows on screen.
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
                if (permission == StoragePermissionState.partial) ...[
                  UiAlert(
                    'Only indexed media can be read. Hidden, renamed, trashed and '
                    'non-media files will be missed.',
                    title: 'Limited scan',
                    status: UiStatus.warning,
                    action: UiButton('Allow all files access',
                        size: UiSize.sm,
                        variant: UiButtonVariant.outline,
                        onPressed: ref.read(permissionStateProvider.notifier).requestFull),
                  ),
                  const UiGap(UiSpace.md),
                ],
                if (browse.running) ...[
                  UiAlert(
                    '${browse.urls.first}  ·  PIN ${browse.pin}',
                    title: 'Browser access is on',
                    status: UiStatus.success,
                    icon: Icons.wifi_tethering_rounded,
                    action: UiButton('Details',
                        size: UiSize.sm,
                        variant: UiButtonVariant.outline,
                        onPressed: () => ref.read(homeTabProvider.notifier).state = HomeTab.computer),
                  ),
                  const UiGap(UiSpace.md),
                ],
                if (scan.error != null) ...[
                  UiAlert(scan.error!,
                      title: 'Scan problem',
                      status: UiStatus.danger,
                      onClose: ref.read(scanControllerProvider.notifier).clearError),
                  const UiGap(UiSpace.md),
                ],
                scan.isScanning ? _ProgressCard(scan: scan) : _StartCard(scan: scan),
                if (hasResults) ...[
                  const UiGap(UiSpace.lg),
                  const _Filters(),
                  const UiGap(UiSpace.sm),
                  _ListHeader(count: items.length),
                ],
              ]),
            ),
            if (hasResults && items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(UiSpace.xl),
                  child: UiEmptyState(
                    compact: true,
                    icon: Icons.filter_alt_off_rounded,
                    title: 'Nothing matches',
                    message: 'Change the filters or the search.',
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
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

class _StartCard extends ConsumerWidget {
  const _StartCard({required this.scan});

  final ScanState scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    final p = scan.progress;
    final String title;
    final String message;
    if (p != null && p.isDone) {
      title = p.isCancelled ? 'Scan stopped' : 'Scan complete';
      message = '${UiFormat.compact(p.totalCount)} files checked, '
          '${UiFormat.compact(scan.items.length)} recoverable items '
          'in ${UiFormat.duration(p.elapsed)}.';
    } else if (scan.fromHistory) {
      title = 'Previous scan';
      message = '${scan.items.length} items from the last scan. Scan again for fresh results.';
    } else {
      title = 'Find lost files';
      message = 'Reads every file on the phone and SD card and identifies it by its '
          'contents, not its name. Finds hidden, renamed, trashed and orphaned files, '
          'and rebuilds photos from thumbnail caches.';
    }
    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const UiIconBox(Icons.radar_rounded, size: 40),
            const UiGap(UiSpace.md),
            Expanded(child: Text(title, style: context.text.titleLarge)),
          ]),
          const UiGap(UiSpace.sm),
          Text(message, style: context.text.bodyMedium?.copyWith(color: context.colors.textMuted)),
          const UiGap(UiSpace.md),
          UiSwitchTile(
            'Deep scan',
            value: ref.watch(settingsProvider.select((s) => s.deepScan)),
            icon: Icons.manage_search_rounded,
            subtitle: 'Also carve files out of unknown blobs, app databases, and data '
                'hidden after images. Slower.',
            onChanged: controller.setDeep,
          ),
          const UiGap(UiSpace.md),
          UiButton(
            p == null && !scan.fromHistory ? 'Start scan' : 'Scan again',
            icon: Icons.play_arrow_rounded,
            size: UiSize.lg,
            expand: true,
            onPressed: controller.start,
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.scan});

  final ScanState scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = scan.progress!;
    final controller = ref.read(scanControllerProvider.notifier);
    final indexing = p.phase == ScanPhase.indexing;
    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ScanRadar(
              found: scan.items.length,
              paused: p.isPaused,
              indexing: indexing,
              size: 148,
            ),
          ),
          const UiGap(UiSpace.lg),
          Row(children: [
            Expanded(
              child: Text(
                indexing ? 'Listing folders…' : 'Analyzing files…',
                style: context.text.titleLarge,
              ),
            ),
            // Distinct keys: UiStatusPill can't switch pulse off and on again
            // in the same State (it uses SingleTickerProviderStateMixin), so
            // pause / resume must build a fresh pill.
            if (p.isPaused)
              const UiStatusPill('Paused', key: ValueKey('pill-paused'), status: UiStatus.warning)
            else
              UiStatusPill(scan.deep ? 'Deep' : 'Standard',
                  key: const ValueKey('pill-running'), status: UiStatus.accent, pulse: true),
          ]),
          const UiGap(UiSpace.md),
          UiProgressBar(p.percentage, showPercent: !indexing, height: 8),
          const UiGap(UiSpace.md),
          Row(children: [
            Expanded(
                child: _Stat(
                    indexing ? 'Files listed' : 'Checked',
                    indexing
                        ? UiFormat.compact(p.scannedCount)
                        : '${UiFormat.compact(p.scannedCount)} / ${UiFormat.compact(p.totalCount)}')),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: scan.items.length.toDouble()),
                duration: context.motion(UiMotion.slow),
                curve: UiMotion.standard,
                builder: (context, v, _) => _Stat('Found', UiFormat.compact(v.round())),
              ),
            ),
            Expanded(child: _Stat('Time', UiFormat.duration(p.elapsed))),
          ]),
          const UiGap(UiSpace.sm),
          Text(
            p.currentPath.isEmpty ? ' ' : p.currentPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall,
          ),
          const UiGap(UiSpace.md),
          Row(children: [
            Expanded(
              child: UiButton(
                p.isPaused ? 'Resume' : 'Pause',
                icon: p.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                variant: UiButtonVariant.secondary,
                onPressed: p.isPaused ? controller.resume : controller.pause,
              ),
            ),
            const UiGap(UiSpace.sm),
            Expanded(
              child: UiButton('Stop',
                  icon: Icons.stop_rounded, variant: UiButtonVariant.danger, onPressed: controller.cancel),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.textMuted)),
          Text(value, style: context.text.titleMedium),
        ],
      );
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(resultFilterProvider);
    final counts = ref.watch(resultCountsProvider);
    final notifier = ref.read(resultFilterProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiSearchField(
          hint: 'Search name, path, app',
          debounce: const Duration(milliseconds: 250),
          onChanged: (q) => notifier.state = notifier.state.copyWith(query: q),
          onClear: () => notifier.state = notifier.state.copyWith(query: ''),
        ),
        const UiGap(UiSpace.sm),
        UiChoiceChips<ResultView>(
          scrollable: true,
          size: UiSize.sm,
          value: f.view,
          options: [
            for (final v in ResultView.values)
              if (v == ResultView.all || (counts.byView[v] ?? 0) > 0)
                UiChoice(v, '${v.label} ${UiFormat.compact(counts.byView[v] ?? 0)}'),
          ],
          onChanged: (v) => notifier.state = notifier.state.copyWith(view: v),
        ),
        const UiGap(UiSpace.xs),
        UiFilterChips<FileCategory>(
          scrollable: true,
          size: UiSize.sm,
          values: f.categories,
          options: [
            for (final c in FileCategory.values)
              if ((counts.byCategory[c] ?? 0) > 0)
                UiChoice(c, '${c.label} ${UiFormat.compact(counts.byCategory[c]!)}', icon: c.icon),
          ],
          onChanged: (s) => notifier.state = notifier.state.copyWith(categories: s),
        ),
      ],
    );
  }
}

class _ListHeader extends ConsumerWidget {
  const _ListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(resultFilterProvider);
    return UiSectionHeader(
      '${UiFormat.compact(count)} items',
      subtitle: f.sort.label,
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        UiButton('Select all',
            size: UiSize.sm,
            variant: UiButtonVariant.ghost,
            onPressed: count == 0
                ? null
                : () => ref.read(selectionProvider.notifier).selectAll(ref.read(filteredItemsProvider))),
        UiMenuButton<ResultSort>(
          icon: Icons.sort_rounded,
          tooltip: 'Sort',
          items: [
            for (final s in ResultSort.values) UiMenuItem(s, s.label, icon: s == f.sort ? Icons.check_rounded : null),
          ],
          onSelected: (s) => ref.read(resultFilterProvider.notifier).state = f.copyWith(sort: s),
        ),
      ]),
    );
  }
}
