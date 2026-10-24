import 'package:flutter/material.dart';
import '../models/channel.dart';
import 'quang_native_player.dart';

/// Compatibility facade for upstream navigation. All playback stays inside QuangTV.
class PlayerScreen extends StatelessWidget {
  final Channel channel;
  final List<Channel>? channelList;
  final int? channelIndex;
  final bool embedded;
  final bool isFullscreen;
  final ValueChanged<bool>? onFullscreenChanged;

  const PlayerScreen({
    super.key,
    required this.channel,
    this.channelList,
    this.channelIndex,
    this.embedded = false,
    this.isFullscreen = false,
    this.onFullscreenChanged,
  });

  @override
  Widget build(BuildContext context) => QuangNativePlayer(channel: channel);
}
