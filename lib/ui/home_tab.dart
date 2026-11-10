import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-navigation destinations, in display order.
enum HomeTab { home, check, computer, settings }

/// Selected bottom-navigation tab. Pages switch tabs by setting it.
final homeTabProvider = StateProvider<HomeTab>((_) => HomeTab.home);
