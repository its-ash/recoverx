import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/share/browse_server.dart';
import '../scan/scan_view_model.dart';
import '../settings/settings_controller.dart';

class BrowseState {
  const BrowseState({
    this.starting = false,
    this.port,
    this.pin,
    this.addresses = const [],
    this.downloads = const [],
    this.error,
  });

  final bool starting;

  /// Set while the server runs.
  final int? port;
  final String? pin;
  final List<LanAddress> addresses;

  /// Files downloaded by computers, newest first, with their SHA-256.
  final List<BrowseDownload> downloads;
  final String? error;

  bool get running => port != null;

  /// `http://ip:port` for each LAN address.
  List<String> get urls => [for (final a in addresses) 'http://${a.address}:$port'];
}

final browseServerProvider = StateNotifierProvider<BrowseController, BrowseState>((ref) => BrowseController(ref));

/// Starts and stops the LAN browse server. The server reads the live scan
/// results, so items found after it starts show up on reload.
class BrowseController extends StateNotifier<BrowseState> {
  BrowseController(this._ref) : super(const BrowseState());

  final Ref _ref;
  BrowseServer? _server;

  Future<void> start() async {
    if (state.running || state.starting) return;
    state = const BrowseState(starting: true);
    try {
      final addresses = await BrowseServer.lanAddresses();
      if (addresses.isEmpty) {
        state = const BrowseState(
            error: 'No network found. Connect the phone to Wi-Fi or turn on its hotspot, '
                'and connect the computer to the same network.');
        return;
      }
      final server = BrowseServer(
        items: () => _ref.read(scanControllerProvider).items,
        revision: () => _ref.read(scanControllerProvider).revision,
        config: () => {'blur': _ref.read(settingsProvider).blurSensitive},
        onDownload: (d) {
          if (!mounted || !state.running) return;
          state = BrowseState(
            port: state.port,
            pin: state.pin,
            addresses: state.addresses,
            downloads: [d, ...state.downloads],
          );
        },
      );
      final port = await server.start(port: _ref.read(settingsProvider).browsePort);
      _server = server;
      if (!mounted) {
        await server.stop();
        return;
      }
      state = BrowseState(port: port, pin: server.pin, addresses: addresses);
    } catch (e) {
      if (mounted) state = BrowseState(error: 'Could not start the server: $e');
    }
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    state = const BrowseState();
    await s?.stop();
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }
}
