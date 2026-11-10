import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/sensitive_rating.dart';
import '../scan/scan_view_model.dart';

/// How readily the content check flags items.
enum SensitivityLevel {
  relaxed(explicit: 0.8, suggestive: 0.85),
  balanced(explicit: 0.6, suggestive: 0.6),
  strict(explicit: 0.4, suggestive: 0.4);

  const SensitivityLevel({required this.explicit, required this.suggestive});

  final double explicit;
  final double suggestive;

  SensitiveThresholds get thresholds => SensitiveThresholds(explicit: explicit, suggestive: suggestive);
}

/// User settings, stored in SharedPreferences (app-private, not evidence).
class AppSettings {
  const AppSettings({
    this.deepScan = false,
    this.blurSensitive = true,
    this.sensitivity = SensitivityLevel.balanced,
    this.videoFrames = 4,
    this.browsePort = 8080,
    this.stopServerInBackground = true,
  });

  /// Deep scan is on when a scan starts.
  final bool deepScan;

  /// Blur flagged photos and videos until revealed (app and browser).
  final bool blurSensitive;
  final SensitivityLevel sensitivity;

  /// Frames sampled per video by the content check.
  final int videoFrames;

  /// Port the browse server tries first.
  final int browsePort;

  /// Stop the browse server when RecoverX leaves the screen.
  final bool stopServerInBackground;

  static const videoFrameChoices = [2, 4, 8];
  static const portChoices = [8080, 8000, 8888];

  AppSettings copyWith({
    bool? deepScan,
    bool? blurSensitive,
    SensitivityLevel? sensitivity,
    int? videoFrames,
    int? browsePort,
    bool? stopServerInBackground,
  }) =>
      AppSettings(
        deepScan: deepScan ?? this.deepScan,
        blurSensitive: blurSensitive ?? this.blurSensitive,
        sensitivity: sensitivity ?? this.sensitivity,
        videoFrames: videoFrames ?? this.videoFrames,
        browsePort: browsePort ?? this.browsePort,
        stopServerInBackground: stopServerInBackground ?? this.stopServerInBackground,
      );
}

final settingsProvider = StateNotifierProvider<SettingsController, AppSettings>((ref) => SettingsController(ref));

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._ref) : super(const AppSettings()) {
    _load();
  }

  final Ref _ref;

  @override
  set state(AppSettings next) {
    final relabel = next.sensitivity != super.state.sensitivity;
    super.state = next;
    if (relabel) {
      // Ratings keep raw scores; new limits re-label them everywhere.
      SensitiveThresholds.current = next.sensitivity.thresholds;
      _ref.read(scanControllerProvider.notifier).touch();
    }
  }

  static const _deep = 'settings.deepScan';
  static const _blur = 'settings.blurSensitive';
  static const _sensitivity = 'settings.sensitivity';
  static const _frames = 'settings.videoFrames';
  static const _port = 'settings.browsePort';
  static const _stopBg = 'settings.stopServerInBackground';

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final d = const AppSettings();
      final loaded = AppSettings(
        deepScan: p.getBool(_deep) ?? d.deepScan,
        blurSensitive: p.getBool(_blur) ?? d.blurSensitive,
        sensitivity:
            SensitivityLevel.values.where((s) => s.name == p.getString(_sensitivity)).firstOrNull ?? d.sensitivity,
        videoFrames: AppSettings.videoFrameChoices.contains(p.getInt(_frames)) ? p.getInt(_frames)! : d.videoFrames,
        browsePort: AppSettings.portChoices.contains(p.getInt(_port)) ? p.getInt(_port)! : d.browsePort,
        stopServerInBackground: p.getBool(_stopBg) ?? d.stopServerInBackground,
      );
      if (mounted) state = loaded;
    } catch (_) {
      // Defaults stay in place.
    }
  }

  Future<void> update(AppSettings next) async {
    state = next;
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setBool(_deep, next.deepScan),
      p.setBool(_blur, next.blurSensitive),
      p.setString(_sensitivity, next.sensitivity.name),
      p.setInt(_frames, next.videoFrames),
      p.setInt(_port, next.browsePort),
      p.setBool(_stopBg, next.stopServerInBackground),
    ]);
  }
}
