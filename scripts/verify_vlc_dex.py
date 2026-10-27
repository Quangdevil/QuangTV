"""Verify class definitions, not residual strings, in the minified release DEX."""
import re
import struct

REQUIRED = {
    'Lorg/videolan/libvlc/interfaces/IMedia$Track;',
    'Lorg/videolan/libvlc/LibVLC;',
    'Lorg/videolan/libvlc/Media;',
    'Lorg/videolan/libvlc/MediaPlayer;',
    'Lorg/videolan/libvlc/VLCObject;',
}


def class_definitions(data):
    if not data.startswith(b'dex\n'):
        raise ValueError('Expected standard DEX')
    def u32(offset):
        return struct.unpack_from('<I', data, offset)[0]
    string_count, string_offset = u32(56), u32(60)
    strings = []
    for i in range(string_count):
        start = u32(string_offset + i * 4)
        while data[start] & 0x80:
            start += 1
        start += 1  # skip the final byte of the UTF-16 length ULEB128
        strings.append(data[start:data.index(b'\0', start)].decode('utf-8', 'replace'))
    type_count, type_offset = u32(64), u32(68)
    types = [strings[u32(type_offset + i * 4)] for i in range(type_count)]
    count, offset = u32(96), u32(100)
    return {types[u32(offset + i * 32)] for i in range(count)}


def verify_vlc_dex(archive):
    defined = set()
    for name in archive.namelist():
        if re.fullmatch(r'classes\d*\.dex', name):
            defined.update(class_definitions(archive.read(name)))
    missing = REQUIRED - defined
    if missing:
        raise ValueError(f'Release VLC JNI classes removed/renamed: {sorted(missing)}')
    print(f'QUANGTV_VLC_RELEASE_DEX_PASS classes={len(REQUIRED)} IMediaTrack=true')


if __name__ == '__main__':
    import sys
    from zipfile import ZipFile
    with ZipFile(sys.argv[1]) as apk:
        verify_vlc_dex(apk)
