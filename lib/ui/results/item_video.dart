import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';
import 'package:video_player/video_player.dart';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';

/// Videos the in-app player can open: whole files on disk. Carved videos
/// live inside another file, and the player needs a file of its own, which
/// would mean writing to the device.
bool canPlayInApp(FileItem i) => i.category == FileCategory.video && !i.isCarved;

/// Plays a found video straight from its path, read-only. Nothing is copied.
class ItemVideo extends StatefulWidget {
  const ItemVideo(this.item, {super.key});

  final FileItem item;

  @override
  State<ItemVideo> createState() => _ItemVideoState();
}

class _ItemVideoState extends State<ItemVideo> {
  late VideoPlayerController _controller = _create();

  VideoPlayerController _create() => VideoPlayerController.file(File(widget.item.path));

  @override
  void didUpdateWidget(ItemVideo old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      // Dispose after the player has switched to the new controller.
      final previous = _controller;
      _controller = _create();
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiVideoPlayer.controller(_controller, radius: UiRadius.lg);
}
