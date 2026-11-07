#!/usr/bin/env python3
"""macOS 내보내기 점검 — Linux에서 만든 SpaceCity.zip이 Mac에서 열릴 꼴인가 (Mac 없이 CI에서 본다).

  python3 game/tools/macos_check.py build/macos/SpaceCity.zip

- 앱 묶음: SpaceCity.app/Contents의 Info.plist, 실행 파일(MacOS/SpaceCity, 실행 권한 0755), 게임 자료(Resources/SpaceCity.pck),
  서명 목록(_CodeSignature/CodeResources)
- 실행 파일이 universal(x86_64 + arm64)이고 두 조각 모두 서명(LC_CODE_SIGNATURE)이 들어 있다 — Apple Silicon은 서명이 없는
  arm64 실행 파일을 바로 죽인다. 프로토타입은 ad-hoc 서명이라 공증은 없다 (처음 열 때 Gatekeeper를 한 번 넘겨야 한다)
"""
import re
import struct
import sys
import zipfile

APP = "SpaceCity.app/Contents/"
NEED = ["Info.plist", "MacOS/SpaceCity", "Resources/SpaceCity.pck", "_CodeSignature/CodeResources"]
CPU = {0x01000007: "x86_64", 0x0100000C: "arm64"}
LC_CODE_SIGNATURE = 0x1D


def slices(binary: bytes):
    """[(아키텍처, 서명 있음, CodeDirectory 플래그)]"""
    magic, count = struct.unpack(">II", binary[:8])
    if magic != 0xCAFEBABE:
        raise ValueError("universal(fat) 실행 파일이 아니다 (magic %#x)" % magic)
    out = []
    for k in range(count):
        cputype, _sub, off, size, _align = struct.unpack(">iiIII", binary[8 + 20 * k:28 + 20 * k])
        part = binary[off:off + size]
        ncmds = struct.unpack("<I", part[16:20])[0]
        p = 32
        flags = None
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack("<II", part[p:p + 8])
            if cmd == LC_CODE_SIGNATURE:
                dataoff, datasize = struct.unpack("<II", part[p + 8:p + 16])
                blob = part[dataoff:dataoff + datasize]
                n = struct.unpack(">I", blob[8:12])[0]
                flags = 0
                for i in range(n):
                    boff = struct.unpack(">I", blob[16 + 8 * i:20 + 8 * i])[0]
                    if struct.unpack(">I", blob[boff:boff + 4])[0] == 0xFADE0C02:   # CodeDirectory
                        flags = struct.unpack(">I", blob[boff + 12:boff + 16])[0]
                        break
            p += cmdsize
        out.append((CPU.get(cputype & 0xFFFFFFFF, hex(cputype)), flags is not None, flags))
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    z = zipfile.ZipFile(sys.argv[1])
    names = {i.filename: i for i in z.infolist()}
    bad = [n for n in NEED if APP + n not in names]
    if bad:
        print("macOS: 빠진 파일 —", ", ".join(bad))
        return 1
    mode = (names[APP + "MacOS/SpaceCity"].external_attr >> 16) & 0o777
    if mode & 0o111 == 0:
        print("macOS: 실행 파일에 실행 권한이 없다 (%o)" % mode)
        return 1
    plist = z.read(APP + "Info.plist").decode("utf-8", "replace")
    bundle = re.search(r"<key>CFBundleIdentifier</key>\s*<string>([^<]*)</string>", plist)
    parts = slices(z.read(APP + "MacOS/SpaceCity"))
    arches = sorted(a for a, _s, _f in parts)
    unsigned = [a for a, s, _f in parts if not s]
    if arches != ["arm64", "x86_64"] or unsigned:
        print("macOS: 실행 파일 조각 %s, 서명 없는 조각 %s" % (arches, unsigned))
        return 1
    adhoc = all(f is not None and f & 0x2 for _a, _s, f in parts)
    print("macOS: OK — %s, universal (%s), 서명 %s, 권한 %o, 게임 자료 %.1f MB" % (
        bundle.group(1) if bundle else "?", " + ".join(arches), "ad-hoc" if adhoc else "인증서",
        mode, names[APP + "Resources/SpaceCity.pck"].file_size / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
