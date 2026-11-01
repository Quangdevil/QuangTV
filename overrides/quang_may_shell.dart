import 'package:flutter/material.dart';
import 'quang_proxy_screen.dart';

class QuangPinnedHeader extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  QuangPinnedHeader({required this.height, required this.child});
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  bool shouldRebuild(covariant QuangPinnedHeader oldDelegate) => oldDelegate.child != child || oldDelegate.height != height;
}

/// Presentation only. Each destination is handled by QuangTV's existing screen.
class QuangMayShell extends StatelessWidget {
  final Widget body;
  final bool fullscreen;
  final int section;
  final ValueChanged<String> onTask;
  const QuangMayShell({super.key, required this.body, this.fullscreen = false, required this.section, required this.onTask});
  static const mint = Color(0xff8ae4d1);
  static const background = Color(0xff0b111a);
  static ThemeData theme() => ThemeData(
    useMaterial3: true, brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: mint, brightness: Brightness.dark).copyWith(
      primary: mint, surface: const Color(0xff101b24), onSurface: const Color(0xffedf5f5)),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(backgroundColor: background, foregroundColor: Color(0xffedf5f5), surfaceTintColor: Colors.transparent),
    dividerColor: const Color(0xff263742),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xff111e29),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xff263742)))),
  );
  @override
  Widget build(BuildContext context) => Theme(data: theme(), child: Builder(builder: (context) {
    Widget task(String id, IconData icon, String label, {bool selected = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(key: ValueKey('may-task-$id'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected, selectedTileColor: const Color(0xff18332f), selectedColor: mint,
        leading: Icon(icon, color: mint), title: Text(label), onTap: () { Navigator.pop(context); onTask(id); }));
    return Scaffold(
      key: const ValueKey('quangtv-may-home'),
      appBar: fullscreen ? null : AppBar(toolbarHeight: 68, titleSpacing: 0,
        title: Row(children: [
          Container(width: 36, height: 30, decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.cloud, color: Color(0xff0b3330), size: 24)),
          const SizedBox(width: 10),
          const Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('QuangTV', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -.7)),
            Text('MỘT KHÔNG GIAN · NHIỀU CẢM HỨNG', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 6, letterSpacing: 1, color: Color(0xff93a7b3))),
          ])),
        ]),
        actions: [const QuangProxyToggle(compact: true), IconButton(tooltip: 'Cài đặt', onPressed: () => onTask('settings'), icon: const Icon(Icons.settings_outlined))],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      drawer: fullscreen ? null : Drawer(backgroundColor: const Color(0xff0d1720), child: SafeArea(child: ListView(children: [
        const Padding(padding: EdgeInsets.fromLTRB(28, 28, 16, 18), child: Text('KHÔNG GIAN CỦA BẠN', style: TextStyle(fontSize: 10, letterSpacing: 2, color: Color(0xff93a7b3)))),
        task('tv', Icons.live_tv, 'QuangTV', selected: section == 0),
        task('iptv', Icons.playlist_play, 'IPTV'),
        task('youtube', Icons.smart_display_outlined, 'QuangTube'),
        task('browser', Icons.public, 'Trình duyệt Mây'),
        task('podcast', Icons.podcasts, 'Podcast', selected: section == 2),
        task('radio', Icons.radio_outlined, 'Radio', selected: section == 3),
        task('private', Icons.lock_outline, 'Private'),
        task('favorites', Icons.favorite_border, 'Ưa thích', selected: section == 4),
        task('downloads', Icons.folder_outlined, 'Đã tải'),
        const Divider(indent: 26, endIndent: 26),
        task('proxy', Icons.vpn_lock_outlined, 'Proxy'),
        task('settings', Icons.settings_outlined, 'Cài đặt'),
        task('update', Icons.system_update_alt, 'Cập nhật OTA'),
      ]))),
      body: DecoratedBox(decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment.topRight, radius: 1.3,
        colors: [Color(0xff10232b), background])), child: body),
    );
  }));
}
