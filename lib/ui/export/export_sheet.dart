import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import '../../core/storage/storage_volumes.dart';
import '../scan/scan_view_model.dart';

Future<void> showExportSheet(BuildContext context) {
  return UiSheet.show<void>(
    context,
    title: 'Export recovered files',
    child: const ExportPanel(),
  );
}

class ExportPanel extends ConsumerStatefulWidget {
  const ExportPanel({super.key});

  @override
  ConsumerState<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends ConsumerState<ExportPanel> {
  late final List<StorageVolume> _volumes = StorageVolumes.list();
  String? _target;

  @override
  void initState() {
    super.initState();
    // Prefer a removable volume so nothing is written to the phone itself.
    final removable = _volumes.where((v) => v.removable);
    _target = (removable.isNotEmpty ? removable.first : _volumes.firstOrNull)?.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(exportControllerProvider);
      if (!s.running) ref.read(exportControllerProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final export = ref.watch(exportControllerProvider);
    final controller = ref.read(exportControllerProvider.notifier);

    if (export.running) {
      final p = export.progress;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiProgressBar(p?.fraction,
              label: p == null ? 'Starting…' : 'File ${p.done + 1} of ${p.total}', showPercent: p != null),
          const UiGap(UiSpace.sm),
          Text(p?.current ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
          const UiGap(UiSpace.sm),
          Text(
            'Copying, hashing (SHA-256) and verifying each copy.',
            style: context.text.bodySmall,
          ),
        ],
      );
    }

    if (export.result != null) {
      final r = export.result!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiSuccessState(
            compact: true,
            title: '${r.okCount} file${r.okCount == 1 ? '' : 's'} recovered',
            message: r.failedCount == 0
                ? 'Every copy matches its source hash.'
                : '${r.failedCount} failed. See manifest.csv for the reasons.',
          ),
          const UiGap(UiSpace.md),
          UiKeyValue('Folder', r.folder, copyable: true, mono: true, stacked: true, maxLines: 4),
          const UiKeyValue('Reports', 'manifest.csv, report.json'),
          if (r.failedCount > 0) ...[
            const UiGap(UiSpace.md),
            for (final f in r.records.where((x) => !x.ok).take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: UiSpace.xs),
                child: UiAlert(f.error!, title: f.item.suggestedName, status: UiStatus.danger),
              ),
          ],
          const UiGap(UiSpace.lg),
          UiButton('Done', expand: true, onPressed: () {
            ref.read(selectionProvider.notifier).clear();
            controller.reset();
            Navigator.of(context).pop();
          }),
        ],
      );
    }

    final items = controller.selectedItems();
    final bytes = items.fold<int>(0, (s, i) => s + i.size);
    final sameVolume = _target != null && items.any((i) => StorageVolumes.volumeOf(i.path, _volumes)?.path == _target);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${items.length} files · ${UiFormat.bytes(bytes)}', style: context.text.titleMedium),
        const UiGap(UiSpace.md),
        if (export.error != null) ...[
          UiAlert(export.error!, title: 'Export failed', status: UiStatus.danger),
          const UiGap(UiSpace.md),
        ],
        Text('Save to', style: context.text.labelLarge),
        const UiGap(UiSpace.xs),
        if (_volumes.isEmpty)
          const UiAlert('No writable storage found.', status: UiStatus.danger)
        else
          UiListGroup(children: [
            for (final v in _volumes)
              UiRadioTile<String>(
                v.label,
                value: v.path,
                groupValue: _target,
                subtitle: '${v.path}/RecoverX/Recovered',
                icon: v.removable ? Icons.sd_card_rounded : Icons.smartphone_rounded,
                onChanged: (x) => setState(() => _target = x),
              ),
          ]),
        if (sameVolume) ...[
          const UiGap(UiSpace.md),
          const UiAlert(
            'Some selected files are on this same storage. Writing here can '
            'overwrite deleted data that is not recovered yet. Insert an SD card '
            'or USB-OTG drive and export there if you can.',
            title: 'Same storage as the evidence',
            status: UiStatus.warning,
          ),
        ],
        const UiGap(UiSpace.md),
        Text(
          'Each file is copied with its real extension and original date, '
          'hashed with SHA-256, and checked against its copy. A manifest.csv '
          'and report.json are written next to the files.',
          style: context.text.bodySmall,
        ),
        const UiGap(UiSpace.lg),
        UiButton(
          'Export ${items.length} files',
          icon: Icons.file_download_rounded,
          expand: true,
          onPressed: items.isEmpty || _target == null ? null : () => controller.export(_target!),
        ),
      ],
    );
  }
}
