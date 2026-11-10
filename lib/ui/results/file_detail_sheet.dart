import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';
import '../labels.dart';
import '../scan/scan_view_model.dart';
import '../sensitive/sensitive_widgets.dart';
import 'item_video.dart';
import 'result_tile.dart';

/// Opens the evidence view for one item.
Future<void> showFileDetail(BuildContext context, FileItem item) {
  return UiSheet.show<void>(
    context,
    title: item.suggestedName,
    subtitle: item.displayName,
    expand: true,
    child: FileDetailBody(item: item),
    actions: [
      Consumer(builder: (context, ref, _) {
        final selected = ref.watch(selectionProvider).contains(item.id);
        return UiButton(
          selected ? 'Remove from export' : 'Add to export',
          icon: selected ? Icons.remove_done_rounded : Icons.add_task_rounded,
          variant: selected ? UiButtonVariant.secondary : UiButtonVariant.primary,
          expand: true,
          onPressed: () => ref.read(selectionProvider.notifier).toggle(item.id),
        );
      }),
    ],
  );
}

class FileDetailBody extends StatelessWidget {
  const FileDetailBody({super.key, required this.item});

  final FileItem item;

  @override
  Widget build(BuildContext context) {
    final meta = item.metadata;
    final metaRows = meta?.toDisplayMap() ?? const <String, String>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canPlayInApp(item))
          SensitiveBlur(item: item, child: ItemVideo(item))
        else if (item.category == FileCategory.video)
          const UiAlert(
            'This video was carved from inside another file, so it cannot be played '
            'in place. Open it with Browse on a computer, or export it.',
            title: 'No in-app playback',
            status: UiStatus.info,
          )
        else if (canPreview(item))
          ClipRRect(
            borderRadius: UiRadius.all(UiRadius.lg),
            child: ColoredBox(
              color: context.colors.surfaceMuted,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320, minHeight: 160),
                child: SensitiveBlur(item: item, child: ItemImage(item, cacheWidth: 1080, fit: BoxFit.contain)),
              ),
            ),
          ),
        const UiGap(UiSpace.lg),
        Wrap(
          spacing: UiSpace.xs,
          runSpacing: UiSpace.xs,
          children: [
            UiStatusPill(item.integrity.label, status: item.integrity.status, dot: true),
            UiStatusPill('Match: ${item.matchConfidence.name}'),
            if (item.isRecovered) const UiStatusPill('Exported', status: UiStatus.success, icon: Icons.check_rounded),
          ],
        ),
        if (item.reasons.isNotEmpty) ...[
          const UiGap(UiSpace.md),
          for (final r in DiscoveryReason.values)
            if (item.reasons.contains(r))
              Padding(
                padding: const EdgeInsets.only(bottom: UiSpace.xs),
                child: UiAlert(r.explanation, title: r.label, status: r.status),
              ),
        ],
        const UiGap(UiSpace.lg),
        UiSection(
          title: 'File',
          child: UiKeyValueList([
            UiKeyValue('Real type', '${item.displayName} (.${item.detectedExtension})'),
            UiKeyValue('MIME', item.detectedMimeType, mono: true),
            UiKeyValue('Size', '${UiFormat.bytes(item.size)} (${item.size} bytes)'),
            UiKeyValue('Name on disk', item.fileName, copyable: true),
            if (item.originalName != null) UiKeyValue('Original name', item.originalName!),
            UiKeyValue('Recover as', item.suggestedName),
            UiKeyValue(item.isCarved ? 'Carved from' : 'Path', item.path,
                copyable: true, mono: true, stacked: true, maxLines: 4),
            if (item.isCarved)
              UiKeyValue('Byte offset', '${item.sourceOffset} (0x${item.sourceOffset!.toRadixString(16)})', mono: true),
            if (item.sourceApp != null) UiKeyValue('App / folder', item.sourceApp!),
            if (item.lastModified != null) UiKeyValue('File modified', formatDateTime(item.lastModified!)),
          ]),
        ),
        if (item.sensitive != null) ...[
          const UiGap(UiSpace.lg),
          SensitiveSection(rating: item.sensitive!),
        ],
        if (metaRows.isNotEmpty) ...[
          const UiGap(UiSpace.lg),
          UiSection(
            title: 'Embedded metadata',
            subtitle: 'Read from inside the file; survives renaming and copying.',
            child: UiKeyValueList([
              for (final e in metaRows.entries) UiKeyValue(e.key, e.value, copyable: e.key == 'GPS', maxLines: 3),
            ]),
          ),
        ],
      ],
    );
  }
}
