import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';
import '../../core/scanner/scan_models.dart';
import 'scan/scan_view_model.dart';

/// Single-page app: scan starts here, live results appear here,
/// pause/resume/cancel here, export here.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = ref.watch(scanProgressProvider);
    final foundFiles = ref.watch(foundFilesProvider);
    final exportPath = ref.watch(exportPathProvider);
    final isScanning = progress != null &&
        !progress.isCancelled &&
        progress.percentage < 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RecoverX'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                await ref.read(scanProgressProvider.notifier).exportSelected();
                _selected.clear();
                setState(() {});
              },
              icon: const Icon(Icons.file_download_done_rounded),
              label: const Text('Export'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Top section: scan button / progress / controls
          if (progress == null || progress.percentage >= 1.0)
            _IdleSection(
              onStart: () =>
                  ref.read(scanProgressProvider.notifier).startScan(),
              hadResults: foundFiles.isNotEmpty,
            )
          else ...[
            _ProgressSection(progress: progress),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          ref.read(scanProgressProvider.notifier).pause(),
                      icon: const Icon(Icons.pause_rounded),
                      label: const Text('Pause'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          ref.read(scanProgressProvider.notifier).resume(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Resume'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          ref.read(scanProgressProvider.notifier).cancel(),
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Export path banner
          if (exportPath != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exported to:\n$exportPath',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        ref.read(exportPathProvider.notifier).state = null,
                    icon: Icon(Icons.close_rounded,
                        color: theme.colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),

          // Results list
          Expanded(
            child: foundFiles.isEmpty
                ? Center(
                    child: Text(
                      isScanning
                          ? 'Scanning…'
                          : 'No files found yet.\nTap Start scan to begin.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    itemCount: foundFiles.length,
                    itemBuilder: (context, i) {
                      final item = foundFiles[i];
                      final selected = _selected.contains(item.id);
                      return Card(
                        child: ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(item.id);
                                  } else {
                                    _selected.remove(item.id);
                                  }
                                }),
                              ),
                              _CategoryIcon(category: item.category),
                            ],
                          ),
                          title: Text(item.fileName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${item.displayName} · ${_formatBytes(item.size)}'
                            '${item.hasWrongExtension ? ' · wrong ext' : ''}',
                          ),
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) =>
                                _DetailSheet(item: item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _IdleSection extends StatelessWidget {
  const _IdleSection({
    required this.onStart,
    required this.hadResults,
  });

  final VoidCallback onStart;
  final bool hadResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.restore_rounded,
              size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            hadResults ? 'Scan complete' : 'Recover lost files',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.radar_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Start scan', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.progress});
  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: progress.percentage.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(progress.percentage * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.titleMedium),
              Text('Found: ${progress.foundCount}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            progress.currentPath.isEmpty ? '—' : progress.currentPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category});
  final FileCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Icon(_icon(), color: theme.colorScheme.onPrimaryContainer),
    );
  }

  IconData _icon() {
    switch (category) {
      case FileCategory.image:
        return Icons.image_rounded;
      case FileCategory.video:
        return Icons.movie_rounded;
      case FileCategory.audio:
        return Icons.audio_file_rounded;
      case FileCategory.document:
        return Icons.description_rounded;
      case FileCategory.archive:
        return Icons.folder_zip_rounded;
      case FileCategory.other:
        return Icons.insert_drive_file_rounded;
    }
  }
}

/// Lightweight inline detail sheet showing key file info.
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.item});
  final FileItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(item.fileName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _Row(label: 'Detected type', value: item.displayName),
            _Row(label: 'Extension', value: '.${item.detectedExtension}'),
            _Row(label: 'Size', value: '${item.size} bytes'),
            _Row(label: 'Path', value: item.path),
            _Row(label: 'Confidence', value: item.matchConfidence.name),
            if (item.hasWrongExtension)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: ListTile(
                    leading: Icon(Icons.drive_file_rename_outline_rounded,
                        color: theme.colorScheme.onSecondaryContainer),
                    title: Text('Suggested: ${item.suggestedName}',
                        style: TextStyle(
                            color: theme.colorScheme.onSecondaryContainer)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}