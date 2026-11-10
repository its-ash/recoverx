import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import '../labels.dart';
import '../scan/scan_view_model.dart';
import 'browse_controller.dart';

/// "Computer" tab: start / stop the LAN browse server and show its address,
/// PIN and download log.
class ComputerPage extends ConsumerWidget {
  const ComputerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(browseServerProvider);
    final c = ref.read(browseServerProvider.notifier);
    final hasResults = ref.watch(scanControllerProvider.select((s) => s.items.isNotEmpty));

    return UiScaffold(
      appBar: const UiAppBar(title: 'Browse on a computer', subtitle: 'View results in a browser on the same Wi-Fi'),
      bottomBar: UiBottomBar(children: [
        if (s.running)
          UiButton('Stop server', icon: Icons.stop_circle_rounded, variant: UiButtonVariant.danger, onPressed: c.stop)
        else
          UiButton('Start server',
              icon: Icons.wifi_tethering_rounded,
              loading: s.starting,
              onPressed: s.starting || !hasResults ? null : c.start),
      ]),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: UiSpace.lg),
        children: [
          if (s.running) const _Running() else _Idle(hasResults: hasResults, error: s.error),
        ],
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.hasResults, required this.error});

  final bool hasResults;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const UiEmptyState(
          icon: Icons.laptop_mac_rounded,
          title: 'Open your results on a laptop',
          message: 'Starts a small web server on this phone. Open the address in any browser '
              'to search, view photos and play videos from the scan without exporting.',
        ),
        const UiGap(UiSpace.lg),
        const UiAlert(
          'Files are read, never changed. Anyone on the same network who has the PIN '
          'can view and download them, so stop the server when you are done. Every '
          'download is SHA-256 hashed as it is sent and listed in a download log the '
          'computer can save.',
          title: 'Read-only, PIN protected',
          status: UiStatus.info,
        ),
        if (!hasResults) ...[
          const UiGap(UiSpace.md),
          const UiAlert('Run a scan on the Home tab first.', status: UiStatus.warning),
        ],
        if (error != null) ...[
          const UiGap(UiSpace.md),
          UiAlert(error!, status: UiStatus.danger),
        ],
      ],
    );
  }
}

class _Running extends ConsumerWidget {
  const _Running();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(browseServerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const UiStatusPill('Server running', status: UiStatus.success, pulse: true),
          const Spacer(),
          Text('Port ${s.port}', style: context.text.labelMedium?.copyWith(color: context.colors.textMuted)),
        ]),
        const UiGap(UiSpace.lg),
        Text('1. Open this address on the computer', style: context.text.titleSmall),
        const UiGap(UiSpace.xs),
        for (final (i, url) in s.urls.indexed) ...[
          _Address(url: url, interface: s.addresses[i].interface, primary: i == 0),
          const UiGap(UiSpace.xs),
        ],
        const UiGap(UiSpace.md),
        Text('2. Enter this PIN', style: context.text.titleSmall),
        const UiGap(UiSpace.xs),
        UiCard(
          child: Row(children: [
            Expanded(
              child: Text(
                s.pin!.split('').join(' '),
                style: context.text.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            UiCopyButton(s.pin!),
          ]),
        ),
        const UiGap(UiSpace.md),
        Text(
          'The computer must be on the same Wi-Fi or connected to this phone\'s hotspot. '
          'Keep RecoverX open while browsing (see Settings → Browse on a computer).',
          style: context.text.bodySmall?.copyWith(color: context.colors.textMuted),
        ),
        if (s.downloads.isNotEmpty) ...[
          const UiGap(UiSpace.lg),
          UiSection(
            title: 'Downloaded (${s.downloads.length})',
            subtitle: 'SHA-256 of the bytes sent. Also in the web page\'s Download log.',
            child: UiKeyValueList([
              for (final d in s.downloads.take(50))
                UiKeyValue(
                  d.item.suggestedName,
                  '${d.sha256}\n${d.client} · ${formatDateTime(d.at)}',
                  mono: true,
                  stacked: true,
                  copyable: true,
                  maxLines: 3,
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

class _Address extends StatelessWidget {
  const _Address({required this.url, required this.interface, required this.primary});

  final String url;
  final String interface;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(
              url,
              style: (primary ? context.text.titleMedium : context.text.bodyMedium)
                  ?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600),
            ),
            Text(interface, style: context.text.labelSmall?.copyWith(color: context.colors.textSubtle)),
          ]),
        ),
        UiCopyButton(url),
      ]),
    );
  }
}
