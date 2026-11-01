/// Keep the experimental package on its own signed update channel.
const autoPreview2Package = 'com.quangduren.quangtv.autopreview2';
const _repoApi = 'https://api.github.com/repos/Quangdevil/QuangTV';

String updateEndpoint(String packageName) => packageName == autoPreview2Package
    ? '$_repoApi/releases?per_page=100'
    : '$_repoApi/releases/latest';

Map<String, dynamic> selectUpdateRelease(dynamic payload, String packageName) {
  final preview = packageName == autoPreview2Package;
  final releases = payload is List ? payload : [payload];
  final candidates = <Map<String, dynamic>>[];
  for (final value in releases) {
    if (value is! Map<String, dynamic> || value['draft'] == true) continue;
    final tag = value['tag_name'] as String? ?? '';
    if (preview) {
      if (!RegExp(r'^auto-preview2-build[0-9]+$').hasMatch(tag)) continue;
    } else {
      if (value['prerelease'] == true || !tag.startsWith('quangtv-v')) continue;
    }
    candidates.add(value);
  }
  candidates.sort((a, b) => releaseBuild(b).compareTo(releaseBuild(a)));
  if (candidates.isEmpty) throw Exception('Chưa có bản cập nhật cho ứng dụng này');
  return candidates.first;
}

int releaseBuild(Map<String, dynamic> release) => int.tryParse(
  RegExp(r'build([0-9]+)$').firstMatch(release['tag_name'] as String? ?? '')?.group(1) ?? '',
) ?? 0;

Map<String, dynamic> selectUpdateApk(Map<String, dynamic> release, String packageName) {
  final tag = release['tag_name'] as String? ?? '';
  final prefix = packageName == autoPreview2Package ? 'QuangTV-Auto-Preview2-' : 'QuangTV-v';
  for (final value in release['assets'] as List<dynamic>? ?? []) {
    if (value is! Map<String, dynamic>) continue;
    final name = value['name'] as String? ?? '';
    final url = Uri.tryParse(value['browser_download_url'] as String? ?? '');
    if (!name.startsWith(prefix) || !name.endsWith('-arm64.apk')) continue;
    if (url == null || url.scheme != 'https' || url.host != 'github.com' ||
        url.path != '/Quangdevil/QuangTV/releases/download/$tag/$name') {
      continue;
    }
    return value;
  }
  throw Exception('Bản phát hành chưa có APK arm64 đúng ứng dụng');
}
