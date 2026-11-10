import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../domain/file_item.dart';
import '../../domain/file_metadata.dart';
import '../labels.dart';
import '../sensitive/sensitive_widgets.dart';

/// Image types Flutter can decode for previews.
const _previewable = {'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif'};

bool canPreview(FileItem i) => _previewable.contains(i.type.id);

/// Reads a carved item's bytes for preview (memory only, never written).
Future<Uint8List> readItemBytes(FileItem item, {int maxBytes = 32 * 1024 * 1024}) async {
  final raf = await File(item.path).open();
  try {
    await raf.setPosition(item.sourceOffset ?? 0);
    final len = item.size < maxBytes ? item.size : maxBytes;
    return await raf.read(len);
  } finally {
    await raf.close();
  }
}

/// Image preview for a found item: the file itself, or the carved range.
class ItemImage extends StatefulWidget {
  const ItemImage(this.item, {super.key, this.cacheWidth, this.fit = BoxFit.cover});

  final FileItem item;
  final int? cacheWidth;
  final BoxFit fit;

  @override
  State<ItemImage> createState() => _ItemImageState();
}

class _ItemImageState extends State<ItemImage> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ItemImage old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) _load();
  }

  void _load() => _bytes = widget.item.isCarved ? readItemBytes(widget.item) : null;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cacheWidth = widget.cacheWidth;
    final fit = widget.fit;
    Widget fallback(BuildContext c, Object e, StackTrace? s) => Center(
          child: Icon(item.category.icon, color: context.colors.textSubtle),
        );
    if (!item.isCarved) {
      return Image.file(File(item.path),
          cacheWidth: cacheWidth, fit: fit, gaplessPlayback: true, errorBuilder: fallback);
    }
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) return fallback(context, snap.error!, null);
        if (!snap.hasData) return const Center(child: UiSpinner(size: 16));
        return Image.memory(snap.data!,
            cacheWidth: cacheWidth, fit: fit, gaplessPlayback: true, errorBuilder: fallback);
      },
    );
  }
}

class ResultTile extends StatelessWidget {
  const ResultTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });

  final FileItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final meta = item.metadata;
    final when = meta?.takenAt ?? item.lastModified;
    final parts = <String>[
      item.displayName,
      if (item.sourceApp != null) item.sourceApp!,
      if (when != null) formatDateTime(when),
    ];
    final flags = [
      for (final r in DiscoveryReason.values)
        if (item.reasons.contains(r)) r,
    ];
    final sensitive = item.sensitive?.flagged ?? false;

    final leading = SizedBox.square(
      dimension: 44,
      child: ClipRRect(
        borderRadius: UiRadius.all(UiRadius.sm),
        child: ColoredBox(
          color: context.colors.surfaceMuted,
          child: canPreview(item)
              ? SensitiveBlur(item: item, compact: true, child: ItemImage(item, cacheWidth: 132))
              : Icon(item.category.icon, color: context.colors.textMuted),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiFileTile(
          name: item.suggestedName,
          size: item.size,
          subtitle: parts.join(' · '),
          leading: leading,
          selected: selected,
          status: item.integrity == Integrity.truncated ? UiStatus.warning : null,
          onTap: onTap,
          onLongPress: onToggle,
          trailing: UiCheckbox(selected, onChanged: (_) => onToggle()),
        ),
        if (flags.isNotEmpty || item.isRecovered || item.integrity == Integrity.truncated || sensitive)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, UiSpace.lg, UiSpace.sm),
            child: Wrap(
              spacing: UiSpace.xs,
              runSpacing: UiSpace.xs,
              children: [
                if (sensitive)
                  UiStatusPill(item.sensitive!.level.label,
                      status: item.sensitive!.level.status, icon: Icons.visibility_off_rounded),
                for (final r in flags) UiStatusPill(r.label, status: r.status),
                if (item.integrity == Integrity.truncated) const UiStatusPill('Damaged', status: UiStatus.warning),
                if (item.isRecovered)
                  const UiStatusPill('Exported', status: UiStatus.success, icon: Icons.check_rounded),
              ],
            ),
          ),
      ],
    );
  }
}
