# Third-party notices

fcxray's original source is licensed under Mozilla Public License 2.0; see LICENSE.

- **Xray-core** — XTLS contributors, MPL-2.0. Source: https://github.com/XTLS/Xray-core . Exact revision is in core.lock.json. Windows builds apply tool/patches/windows-session-tun.patch to that revision via Go overlay. The upstream revision and the patch in the matching https://github.com/follow-xray/fcxray release source provide the corresponding source. The MPL text is included in LICENSE and the app's license assets.
- **Flutter / Dart** — their respective contributors, BSD-style licenses. https://github.com/flutter/flutter and https://github.com/dart-lang/sdk . Flutter packages and their licenses are available through the app's license page.
- **flutter_secure_storage** — its contributors, BSD-3-Clause. https://github.com/juliansteenbakker/flutter_secure_storage . Versions of it and transitive Flutter packages are locked in pubspec.lock.
- **file_selector / path_provider** — Flutter contributors, BSD-style licenses. https://github.com/flutter/packages . Used for local database selection and application support directories; package licenses appear in the in-app license page.
- **Optional GeoIP / GeoSite data** — the default download source is https://github.com/Loyalsoldier/v2ray-rules-dat . Data is downloaded on user action or a configured update schedule, and is not bundled in this repository or app. Consult the data source for its license and attribution.
- **Go modules** — third-party components retain their own licenses. Versions and checksums are in native/go.mod and native/go.sum. `tool/collect_licenses.py` gathers module license texts into the bundled assets without copying machine-specific source paths.
- **Wintun** — WireGuard LLC / Jason A. Donenfeld and contributors. https://www.wintun.net/ . Windows builds use the official signed 0.14.1 DLL, under the binary distribution license supplied in its archive (WINTUN-LICENSE.txt). Wintun source has its own GPL-2.0 license. The official archive checksum is pinned in tool/build.py; the DLL and its original license are distributed together.

No upstream affiliation, endorsement, or trademark ownership is implied. Do not remove third-party license text when redistributing builds. Include this notice, LICENSE, collected license assets, and (Windows) WINTUN-LICENSE.txt with distribution artifacts.
