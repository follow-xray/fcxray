# fcxray

基于 Flutter 与 [Xray-core](https://github.com/XTLS/Xray-core) 的开源 VPN 客户端，面向 Android、Windows 和 macOS；iOS 无法上架 AppStore 故暂不支持。许可证为 **MPL-2.0**。这是独立社区客户端，与 XTLS 官方没有隶属关系（没这个）。

项目目录、Dart 包名和应用显示名称均为 `fcxray`。Android applicationId / namespace、macOS Bundle ID 和 Windows AppUserModelID 统一使用 `com.fcxray.client`。桌面产物为 `fcxray.app` / `fcxray.exe`。

[桌面界面预览](docs/previews/desktop.png) · [手机界面预览](docs/previews/mobile.png) · [深色主题预览](docs/previews/desktop-dark.png)

## 功能

在“设置 → 外观主题”选择浅色、深色或跟随系统。首次使用时跟随系统，选择会保存在本机。

- 自适应桌面 / 手机界面：连接总览、节点管理、订阅管理、路由与规则、设置、运行日志。
- 覆盖固定内核注册表的全部 13 种客户端出站；支持常见分享链接、多行/Base64 订阅内容和 Xray 出站 JSON。
- RAW/TCP、WebSocket、gRPC、XHTTP、HTTPUpgrade、mKCP、Hysteria、MASQUE、xdrive 传输，以及 TLS / REALITY；组合限制与内核一致。
- VPN/TUN 模式；桌面另提供本地 SOCKS5 / HTTP 代理模式。
- 直连、规则和全局三种路由模式；TUN DNS 转交 Xray 内置 DoH。
- 内核启动结果驱动的状态、真实会话字节计数与速率（在入站侧统计，包含局域网直连流量）。显示“隧道已启动”不意味着远端已通过可达性检测。
- 节点凭据通过 `flutter_secure_storage` 保存；无账号、遥测、内置节点和远程控制服务。
- 全协议参数表单和完整出站 JSON 编辑；包括 WireGuard、Hysteria 2、MASQUE、Shadowsocks 2022 和 VLESS + xdrive。每个表单参数带 `?` 帮助，保存前由真实内核校验。
- 多个 HTTPS 订阅、批量导入、按来源筛选和定时更新；连接中优先通过当前本地代理下载，失败从头重试系统网络。更新下次连接生效，不重启当前隧道。
- 查看真实运行中配置快照或下次启动预览，支持凭据隐藏/显示与 JSON 复制。
- GeoIP / GeoSite `.dat` 本地导入、HTTPS 更新、自定义来源、可选 SHA-256 固定校验、分类浏览与分流。
- Xray 源码版本固定；不修改上游源码。随时观察xray-core，手动随内核更新而更新。

## 平台实现

| 平台 | 数据转发与权限 | 构建方式 |
| --- | --- | --- |
| Android 7+ / API 24+ | `VpnService` 建立 IPv4/IPv6 TUN；gomobile AAR 内嵌 Xray，传递 `XRAY_TUN_FD`，保护出站 socket；前台通知提供断开操作 | Android SDK / NDK / JDK，调试包含 arm64-v8a、x86_64，tag 构建提供 arm64-v8a 和 armeabi-v7a 独立包 |
| Windows 10/11 | 原生 Xray TUN + Wintun；TUN 模式须“以管理员身份运行”；本地代理无需管理员 | Windows + Visual Studio C++ 桌面工具链 |
| macOS | 原生 utun；TUN 连接时由系统请求管理员授权，仅内核提权，界面与钥匙串仍使用当前用户 | macOS + Xcode + CocoaPods |

macOS 使用短期管理员内核与位于随机 `0700` 私有目录中的 Unix socket 通信；断开时退出提权进程。普通桌面内核使用 stdin/stdout JSON 消息，无控制 TCP 端口。桌面关闭主窗口会隐藏到 FOLLOW 托盘，VPN 继续运行。左键点击图标可恢复窗口，右键菜单显示实际连接节点，支持连接、断开、切换节点和退出。已连接时切换节点会断开并连接所选节点，未连接时只保存选择。选择“退出 fcxray”会关闭内核并释放接口和路由。Android 服务独立于界面运行，需通过客户端、通知或系统 VPN 设置停止。

## 环境与源码

- Flutter **3.44.0** / Dart **3.12** 或兼容版本。
- Go **1.27**（由固定的 Xray-core 版本要求）。
- Python 3.10+、Git。
- Android：SDK 36、NDK 28、JDK 17+（以 Flutter / Gradle 检测结果为准）。SDK 许可需由开发者自行确认。

```sh
cd follow-xray/fcxray
flutter pub get
python3 tool/build.py bootstrap
```

工作区中会优先引用 `../Xray-core`（即 `follow-xray/Xray-core`，与 `fcxray` 同级），通过被 Git 忽略的 `third_party/Xray-core` 相对符号链接使用。源码移动导致旧链接失效时，运行 `python3 tool/build.py bootstrap` 会自动重建链接。独立克隆项目时会从官方仓库拉取 `core.lock.json` 指定提交。可用 `XRAY_CORE_DIR` 指向已有源码（Windows 默认克隆到项目内以避免符号链接权限问题）。版本不匹配或源码有已跟踪文件修改时，构建脚本停止，不会修改现有核心仓库。

固定核心提交：`82b5b76bc510d0f2d5afd04485d71f9e125de19d`。

## macOS

```sh
python3 tool/build.py core
flutter run -d macos

# 发布模式本地构建，包含内核并进行 ad-hoc 签名
python3 tool/build.py macos
open 'build/macos/Build/Products/Release/fcxray.app'
```

构建脚本默认使用当前机器架构；如需 Intel 版本，在对应架构环境构建。调试运行从项目的 `native/bin` 查找内核；打包运行从 `.app/Contents/MacOS` 查找。也可设置 `FCXRAY_CORE` 为内核绝对路径。

**macOS DNS 注意事项：** 上游原生 TUN 不修改系统 DNS。如果当前 DNS 是局域网地址，其更具体路由可能绕过 TUN。启用 TUN 前，请将当前网络 DNS 手动改为 `1.1.1.1`，断开后恢复原设置。本预览版不宣称具备完整 DNS 防泄漏能力。IPv6、物理网卡变化和睡眠恢复需在目标系统实测。

本工程使用非 sandbox 桌面分发路径，尚未实现 Network Extension / App Store 分发。正式分发需 Developer ID 签名与公证，不能直接使用开发用 ad-hoc 签名。

## Android

```sh
# macOS 的默认 SDK 路径会自动识别；其他系统请设置 ANDROID_HOME
python3 tool/build.py android-core
flutter run -d <设备ID>

# 构建可安装的调试 APK（内核默认包含 arm64-v8a、x86_64）
python3 tool/build.py apk
```

APK：`build/app/outputs/flutter-apk/fcxray-debug.apk`（构建脚本从 Flutter 默认的 `app-debug.apk` 复制命名）。安装后应用名称为 `fcxray`，包名为 `com.fcxray.client`。首次连接需要接受系统 VPN 授权。应用自身绕过 VPN，以覆盖 Go 运行时的服务器域名引导解析；其他应用的 IPv4/IPv6 默认路由交给 TUN。Go socket 同时调用 `VpnService.protect()`。

Android 内核构建使用固定版本的官方 `golang.org/x/mobile`；当前上游 Android 网络依赖使用 Go 内部符号，所以链接包含 `-checklinkname=0`。不支持旧式 VMess alterId、SIP003 外部插件或 Android always-on 自动恢复。

### 推送 tag 发布分架构 APK

将 tag 推送到 GitHub 后，**Android tag APKs** 工作流会并行构建 ARM64 和 ARMv7 的 Release APK。每个任务从固定的 Xray-core 提交编译对应的原生库，并检查最终 APK 只含目标 ABI，以及 Xray、Flutter 引擎、Dart AOT 库的 ELF 架构。

两个构建任务都成功后，工作流会创建对应 tag 的 GitHub Release。用户在 **Releases → 对应版本 → Assets** 中即可直接下载适合设备的 APK。以 `v0.7.1` 为例：

- `fcxray-0.7.1-android-arm64-v8a.apk`（64 位 ARM）
- `fcxray-0.7.1-android-armeabi-v7a.apk`（32 位 ARMv7）

版本 tag 可使用 `v1.2.3` 或 `v1.2.3-beta.1`，版本号同步为 Android 的 versionName。其他 tag 也会触发构建，APK 保留 pubspec 中的应用版本。发布新版本时递增 pubspec.yaml 中的构建号，以支持 Android 升级。新 Release 会在两个 APK 都上传成功后发布。形如 `v1.2.3-beta.1` 的 tag 会标记为预发布。重跑时复用相同 tag 的 Release，对已发布版本只补齐缺失或未成功上传的 APK。

已推送的 tag 若因 CI 环境配置失败，可在修复合入默认分支后，打开 **Actions → Android tag APKs → Run workflow**，选择默认分支，在 `tag` 中填入原标签（例如 `v0.1.0`）。工作流使用当前的构建环境配置，检出指定 tag 的源码并发布到该 tag。直接在旧运行中选择 Re-run 会继续使用旧工作流。

正式分发时，在仓库 **Settings → Secrets and variables → Actions** 配置以下四项 repository secrets，使不同 tag 和架构使用同一签名证书：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 发布 keystore 的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 签名密钥别名 |
| `ANDROID_KEY_PASSWORD` | 签名密钥密码 |

四项均未配置时，APK 仍为 Release 模式，使用各 runner 的临时调试证书，仅供测试，不能保证覆盖安装之前的包。只配置部分密钥会使任务失败。

本地复现：

```sh
python3 tool/build.py tag-apk --tag v0.7.1 --abi arm64-v8a
python3 tool/build.py tag-apk --tag v0.7.1 --abi armeabi-v7a
```

产物在 `build/tag-apks/`；原有 `python3 tool/build.py apk` 继续生成开发用调试包。

## Windows

在 Windows 终端中运行：

```powershell
flutter pub get
python tool/build.py windows
```

脚本从源码构建核心、下载官方 Wintun **0.14.1** 并核验官网 SHA-256，然后由 CMake 一起打包 `fcxray-core.exe`、`wintun.dll` 和许可文本。产物位于 `build/windows/x64/runner/Release`（随目标架构变化）。请完整分发目录，不能只复制 Flutter EXE。

- TUN：右键 `fcxray.exe`，选择“以管理员身份运行”。
- 本地代理：普通权限运行即可，在设置中选择“本地代理”。
- 跨平台仅构建 Windows Go 核心：`python3 tool/build.py core --goos windows --arch amd64`；Flutter Windows GUI 仍须在 Windows 构建。

## 使用

1. 在“我的节点”手动添加参数，或粘贴分享链接、Base64 订阅内容和 Xray JSON；也可在“订阅管理”批量添加 HTTPS 订阅。
2. 选择节点与路由策略，在总览点击连接。
3. Android 同意系统 VPN 授权；macOS TUN 同意管理员授权；Windows TUN 以管理员运行。
4. 本地代理模式需手动设置应用代理：SOCKS5 `127.0.0.1:10808`，HTTP `127.0.0.1:10809`。这两个端口也会在 TUN 模式提供。

导入完整 JSON **仅提取代理出站**，忽略已有 DNS / 入站 / 路由；依赖其他出站的链式配置会被拒绝。外部脚本、文件引用、关闭 TLS 验证等配置不受支持。节点配置只进入内核内存，不写入明文配置临时文件。

没有提供扫码、开机启动、自动重连或断线阻断。端口目前固定；端口冲突会明确报错。退出/崩溃后不会故意保持阻断，不能把本应用作为 kill switch。

## 路由模式和自定义规则

在首页连接面板或桌面托盘右键菜单中选择“直连”“规则”或“全局”。直连可以在没有节点时启动，普通流量使用系统网络出口。全局把普通流量交给所选节点。规则模式支持分别启用局域网直连与 GeoIP/GeoSite，其余流量默认使用所选节点。三种模式均保留 VPN 内的 DNS 接管。

在设置中点击“添加规则”，选择“精确域名”“域名及子域名”或“IP / 网段”，每行输入一个目标，再选择直连、代理或拒绝。可通过复选框暂时停用，通过菜单编辑、上移、下移或删除。自定义规则按列表顺序优先于局域网和 Geo 规则；例如把精确域名 pay.example.com 的代理规则放在 example.com 的子域名拒绝规则上方，可单独放行支付服务。

连接中切换模式会重新连接。连接中编辑条目或分流选项后，可以在设置中点击“立即应用”。内核原子替换路由规则，新请求按新规则分流，已建立的流继续使用原路径。仅在已连接的规则模式下可应用。应用保留当前节点及正在使用的规则库版本，失败保留之前的规则。旧版“绕过局域网”迁移到规则模式并启用局域网直连；旧版 Geo 模式同时启用 Geo 分流。

在设置的“自定义规则”中使用“导出 JSON”保存匹配方式、目标、动作、顺序和启用状态。“导入 JSON”会先校验整个文件，再选择追加或替换。重复目标或无效条目会提示错误并保留当前列表。支持导出的版本化对象及其中的裸规则数组。文件最大 1 MiB，默认名为 `fcxray-rules.json`。

“我的节点 → 示例配置”内置 [VLESS + Vision + TCP 客户端 JSON](assets/examples/vless-vision-tcp.json)。可复制完整配置，也可点“用示例新建节点”预填表单。示例使用 TLS 和 443 端口，保存前请替换域名、UUID、端口与证书对应的 SNI。选择 [REALITY 模板](assets/examples/vless-vision-tcp-reality.json) 后，点击“用示例新建节点”，填写服务端的地址、UUID、SNI、X25519 公钥和 shortId。模板默认使用 TCP、Vision 和 443 端口，关闭 Mux。独立运行示例时 SOCKS5 监听 127.0.0.1:10808；导入客户端时，入站和路由由当前应用设置生成。

## 节点延迟测试

在节点行点击速度表图标，可通过该节点请求 `https://www.gstatic.com/generate_204`。毫秒数从发起 HTTPS 请求算到收到 204 响应头，包含本次连接握手。目标不可达、认证失败或超时均显示“测试失败”。

“批量测速”覆盖当前搜索及订阅筛选下的全部远端节点，包括尚未展开的条目。桌面最多三个并发，Android 逐个测试。可停止排队，已开始的请求会收尾。“按延迟排序”优先显示有结果的节点，延迟相同的节点保留原顺序。结果保存在本次运行的内存中。

测试使用候选节点自己的出站配置。桌面为每次测试启动普通权限的临时内核进程，Android 使用私有的 `:latency` 服务进程。测试不创建 TUN 或本地监听端口，也不修改 VPN 的节点选择。桌面开启全局 TUN 时，测试进程的出站连接遵循系统路由，测得的时间可能包含当前 VPN 的路径。

## 手动参数与帮助

“我的节点 → 手动添加”提供参数表单与完整出站 JSON 两种编辑方式。协议与传输参数动态显示，`?` 支持桌面悬浮、手机点击和键盘激活。出站范围以 `core.lock.json` 固定的 Xray-core 为准，测试会对照内核的真实注册表检查遗漏。

| 类别 | 支持的出站 |
| --- | --- |
| 代理 / 隧道 | VLESS、VMess AEAD、Trojan、Shadowsocks（含三种 SS2022 方法）、SOCKS5、HTTP/HTTPS、WireGuard、Hysteria 2、MASQUE |
| 内置路由出口 | freedom（direct）、blackhole（block）、dns、loopback |

内置路由出口不是通用远端代理：freedom 直连，blackhole 阻断，dns 只处理 DNS。loopback 作为独立配置使用时，为其回注标签自动添加直连路由，避免默认出站无限回环。

支持 `http(s)://`、`socks(5)://`、`hysteria2://` / `hy2://`、`wireguard://` / `wg://`、`masque://`，以及原有四类分享链接。复杂参数推荐完整出站 JSON。`direct` / `block` 与传输别名 `raw` / `mkcp` / `websocket` / `splithttp` 均会识别。已被内核移除的旧 HTTP/2、QUIC 传输不伪装成可用选项；H3 应使用对应 XHTTP/QUIC 配置。

节点保存时先构建出站并让 Xray-core 校验，不会为了测试表单而改变系统路由。编辑手动节点会保留未在表单中展开的高级 JSON 字段；编辑订阅节点会复制成独立手动节点，避免下次订阅更新覆盖修改。UUID 生成按钮只生成客户端 ID，需要同步配置到服务端。

## 多订阅与更新

- “订阅管理 → 添加订阅 / 批量导入”：可一次输入 1–30 个 HTTPS 地址，每行一个；可重复添加不同批次。
- 接受分享链接列表、Base64 内容与 Xray JSON；不解析 Clash YAML。单个响应最大 1 MiB / 2000 个节点。
- 每个订阅可编辑名称、地址和更新周期，独立更新或更新全部。订阅地址可能包含令牌，保存在系统安全存储，卡片只展示域名。
- 更新仅替换对应来源的节点。地址与认证参数未变化的节点保留 ID 和当前选择；删除订阅不会删除其他来源或手动节点。
- 下载、解析或持久化失败时保留之前的数据。HTTP 重定向限 5 次，全程 HTTPS，单次流读取有超时及总大小限制。
- 自动更新在**应用运行期间**执行，每分钟检查到期任务，VPN 连接时也可执行；不提供关闭应用后的系统后台任务。
- 已连接时，读取正在运行的 JSON 快照，使用其 loopback HTTP 代理入口（默认 `127.0.0.1:10809`）下载，按当前路由规则转发。失败后从头重试系统网络；系统网络仍受操作系统路由影响，不保证绕开系统 VPN。
- 每次重试使用独立的接收缓冲/暂存文件，不会把半截响应拼到下一次下载。订阅内容只进入内存，Geo 文件通过独立暂存区验证后安装。
- 更新只保存“下次连接”的节点和规则。当前内核 JSON、会话 ID、活动节点和已引用的 Geo 文件不变；即使当前节点被订阅移除，也保持本次连接。总览显示待生效提示，下载期间仍可手动断开。

## 查看当前配置

点击页面右上角 `{}` 按钮，或“设置 → 查看配置”。“当前连接”从原生内核读取本次成功启动收到的 JSON 快照；“下次连接”显示已更新数据生成的预览。连接中也可切换对照，更新不会被误标为已经应用。Android 界面重建后也从仍在运行的 VpnService 内核读取，不依赖界面中的旧缓存。

默认隐藏 UUID、密码及请求头等凭据，可切换显示并复制当前内容。配置留在内存中，不生成明文临时配置文件。规则库目录另外显示，帮助核对实际加载位置。

## GeoIP / GeoSite

1. 在“路由与规则”分别导入兼容 Xray/V2Ray 的 `geoip.dat`、`geosite.dat`，或者点击“立即更新”。
2. 默认下载源为 [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 官方 release；可编辑 HTTPS 直链与自动更新周期。数据库不内置到应用或源码仓库。
3. 文件先写入暂存区，限制 64 MiB，然后由 Go 按对应 protobuf 类型检查分类、CIDR / 域名记录，并计算 SHA-256；可额外填写预期摘要锁定指定版本。
4. 通过校验后写成 `geoip-<sha256>.dat` / `geosite-<sha256>.dat`，保存在应用支持目录的 `geodata` 子目录。配置通过 `ext:<文件名>:<分类>` 引用，内核使用 `XRAY_LOCATION_ASSET` 指向该目录；不会修改 Xray-core 源码目录。
5. 分类列表可搜索、复制。默认规则为 `cn` IP / 域名直连，其余走代理；可设置阻止域名分类，例如数据库中存在的 `category-ads-all`。
6. 打开“使用 GeoIP / GeoSite 分流”，并在首页或托盘中选择“规则”。需要的文件或分类不存在时明确报错，不会静默改成别的策略。

规则模式的分流顺序是 TUN DNS 接管 → 自定义域名/IP 规则 → 可选的局域网直连 → GeoSite 阻止 → GeoSite 直连 → GeoIP 直连 → 其他流量代理。该模式开启 HTTP / TLS / QUIC 的 route-only 嗅探，用域名匹配规则，同时保持原始连接目标。

更新不覆盖现有文件，避免 Android 常驻内核的数据缓存读到旧内容。下载或校验失败保留上次版本；连接中也可导入、下载和编辑下一次的分类规则，除显式应用规则外，当前连接继续使用原来的数据。历史文件暂时保留以便排查，当前版本不会自动清理旧文件。SHA-256 用于完整性/版本核对，不代表发布者签名。

## xdrive

xdrive 是 **VLESS 的传输方式**，在“协议 = vless → 传输协议 = xdrive”中选择，不是独立出站协议。当前内核要求：

- 填写服务端提供的 VLESS `encryption`，不能为 `none`；必须与服务端 `decryption` 配对。
- 启用 Mux，不能使用负并发或 `xudpProxyUDP443=skip`；选择 xdrive 时表单预设 Mux 并发 128。
- `flow` 必须为空，不能搭配 Vision flow。

存储服务支持 `google-drive`、`s3`、`template`、`local`，都有对应字段与 `?` 提示：

- Google Drive：Folder ID，凭据数组 `[ClientID, ClientSecret, RefreshToken]`。
- S3：远端前缀，`endpoint/region/bucket/pathStyle`，凭据数组 `[AccessKeyID, SecretAccessKey, 可选 SessionToken]`。
- HTTP/WebDAV 模板：提供 `put/get/delete/list` 等完整模板及 `{secret0}` 等索引凭据。
- local：客户端与服务端均可访问的本地目录，用于本地/共享存储部署与测试。

分片、刷新、轮询、并发、TTL、缺片超时、Xmux 和 FinalMask 参数均可配置。完整出站 JSON 保留未在表单展开的高级字段。对于 `vless://` 扩展链接，可用 `type=xdrive`、`encryption=...` 和 URL 编码的 `xdriveSettings` JSON；复杂配置优先使用 JSON 导入。

xdrive、WireGuard、Hysteria 等新增认证字段在配置查看页默认脱敏。项目不代建云存储账号，不内置第三方服务凭据。当前已完成加密 VLESS + Mux + xdrive local 的真实 HTTP 转发测试；云服务的连通性取决于用户提供的账户、权限与网络。

## 界面参考

本次实现参考了本工作区开源客户端的交互分区，代码为本项目实现：

- FlClash：`lib/views/profiles/` 中的配置卡片、订阅编辑及配置预览；`lib/providers/actions/geo_resource.dart` 中的规则源与更新入口。
- v2rayN：`v2rayN/v2rayN.Desktop/Views/AddServerWindow.axaml` 的协议参数分区，以及 `SubSettingWindow.axaml` 的多订阅与更新周期。
- karing：`lib/screens/my_profiles_screen.dart` 与 `add_profile_by_link_or_content_screen.dart` 的来源管理与导入入口。

## 开发与验证

```sh
python3 tool/build.py core
python3 tool/build.py check
python3 tool/smoke.py
```

- Dart：内核注册表一致性、全部出站/传输/SS2022/xdrive 存储配置的原生校验；代理优先、半截响应重试、连接中更新、不重启会话、下一次连接应用；参数表单、完整 JSON、tooltip 和双布局。
- Go：真实 SOCKS 数据转发、加密 VLESS + Mux + xdrive local 端到端转发、统计与资源回收；Geo 数据校验、原生分类路由与活动快照，支持 `go test -race ./...`。
- Smoke：Dart 实际生成三平台配置，经 Go 校验；本机 Xray 客户端 → VLESS 服务端 → HTTP 目标的真实往返、计数、重连与父进程 EOF 清理。测试不改变系统网络路由。
- 可选联网测试：`python3 tool/geo_smoke.py` 下载默认规则源并检查摘要、真实 protobuf 与原生路由加载，仅写入被忽略的 `build/geo-smoke`，不启动 VPN。
- CI：静态检查、测试、macOS / Windows / Android 构建；推送 tag 时自动发布对应的 Android Release。

目标机器的 VPN 授权、TUN 路由恢复、DNS/IPv6 泄漏、Wi-Fi/蜂窝切换、睡眠恢复和远端节点连通性仍需单独验证；模拟内核状态或本地代理测试不能替代这些测试。

## 目录

```text
lib/             Flutter 界面、状态、协议导入、配置与平台桥接
android/         Kotlin VpnService 和 gomobile AAR 接入
macos/           Flutter macOS runner
windows/         Flutter Windows runner 与核心 / 驱动打包
native/bridge/   跨平台 Xray 生命周期、保护回调、统计
native/cmd/      桌面 JSON 通信进程
third_party/     构建时引用的固定 Xray 源码（忽略）
tool/            构建、许可收集与本地集成验证
test/            Dart / Flutter 测试
```

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，漏洞报告见 [SECURITY.md](SECURITY.md)，依赖许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

实现依据：[Xray TUN](https://xtls.github.io/en/config/inbounds/tun.html)、[Android VPN](https://developer.android.com/develop/connectivity/vpn)、[Wintun](https://www.wintun.net/)。
