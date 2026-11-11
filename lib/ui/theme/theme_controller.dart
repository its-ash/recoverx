import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Optional accent color for the theme package. Null uses the default accent.
final appAccentProvider = Provider<Color?>((_) => null);
