# 音乐厅 · 华为音乐 iOS 客户端（非官方）

> **⚠️ 非官方项目**：与华为及其关联公司无隶属、合作或代理关系，未获授权、认可或技术支持。
>
> 这个项目只是把**你自己华为账号里已有权益的内容**，用一个 iPhone 界面播出来：
> 不含任何音源、不下载、不破解、不绕过付费/会员/地域/DRM 限制。能听什么完全取决于你的账号。
> 使用第三方客户端是否违反服务条款、账号是否可能受限，由使用者自行判断和承担。

按 [Daydreamcgy/huawei-music-win](https://github.com/Daydreamcgy/huawei-music-win)（华为音乐的第三方 Windows 客户端）的接口契约与观感做的 iOS 版：
同一套登录链路、同一套接口参数、同一套「深色 + 封面当主角 + 播放条退到幕后」的设计语言，但布局按**手机**重做。

- 技术栈：SwiftUI + AVPlayer + WKWebView + AuthenticationServices，**无第三方依赖**，纯系统框架
- 工程：Xcode 工程（`project.yml` 走 XcodeGen）+ GitHub Actions 自动编未签名 ipa
- 许可：AGPL-3.0-only（见 [NOTICE](NOTICE) 与 [LICENSE](LICENSE)）
- 最低系统：iOS 16.0

**当前状态**：GitHub Actions 的 macOS 编译已通过（`CODE_SIGNING_ALLOWED=NO`），ipa 约 0.7 MB。
真机运行与登录链路尚未实测，第一次装在 iPhone 上如果遇到问题请开 Issue 附日志。

> 工程名故意叫 `MusicHall`（音乐厅），桌面图标名也是「音乐厅」，避免冒用厂商标识；
> 界面文案里出现的「华为音乐」只用于说明它所兼容的服务。

---

## 现在能做什么

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| 华为账号登录 | ✅ | 官方登录页装在独立 `WKWebView` 里，拦截 `hms://redirect_uri` 回跳，自动换音乐会话 |
| 会话保持 | ✅ | 音乐令牌存钥匙串，重启免登录；失效时提示重新登录 |
| 系统浏览器登录 | ✅ | 内嵌页打不开时可切 `ASWebAuthenticationSession`（Safari 授权） |
| 首页 | ✅ | 问候语 + 继续听 + 最近播放（账号历史）+ 收藏速览 |
| 音乐厅 | ✅ | 我的歌单宫格 + 收藏精选（换一批） |
| 我的收藏 | ✅ | 分页拉全、按歌曲 ID 去重、下拉刷新、播放全部、长按取消收藏 |
| 我的歌单 | ✅ | 宫格 + 详情页（分页加载、播放全部） |
| 搜索 | ✅ | 防抖 350ms、分页加载、最近搜索 |
| 播放历史 | ✅ | 账号维度的播放记录，最多展示最近 200 条 |
| 播放 | ✅ | 单曲解析、播放/暂停、上下首、拖进度、一个按钮切四种播放模式 |
| 播放页 | ✅ | Apple Music 式：封面重模糊做底，歌词占满屏、左对齐、当前行加粗放大、点行跳转；封面 / 歌词两页淡入淡出切换 |
| 播放条（迷你） | ✅ | 常驻 Tab 上方，2px 进度线，暂停/下一首 |
| 播放队列 | ✅ | 正在播放 / 接下来、点行跳转、× 移除、清空待播 |
| 长按菜单 | ✅ | 任意歌曲行：立即播放 / 下一首播放 / 添加到播放队列 |
| 队列持久化 | ✅ | 关掉再开恢复上次队列 + 那一首 + 进度（暂停，不自动出声） |
| 后台播放 | ✅ | 锁屏 / 控制中心信息与远程控制（播放、暂停、上一首、下一首、拖进度） |
| 玻璃质感 | ✅ | 顶栏圆钮与底部控制条：iOS 26 起走系统 Liquid Glass，iOS 16–18 用超薄材质 + 高光描边近似 |
| 设置 | ✅ | 音质（标准/无损）、播放历史上报开关、清缓存、退出登录、关于 |
| 每日推荐 / 榜单 | ⬜ | 上游接口 `recommend/querydaily` 仍是 400，不做假推荐替代 |
| 下载 / 离线 | ⬜ | 不提供解密、转存、离线导出 |
| 专辑 / 歌手页 | ⬜ | 接口已在上游验证，本版未接界面 |

---

## 装到 iPhone（不需要 Mac）

思路：让 GitHub 的 macOS 跑编译，你在 Windows 上只负责签名安装。

### 1. 把仓库推上 GitHub

```bash
cd huawei-music-ios
git init && git add . && git commit -m "ios: initial"
git branch -M main
git remote add origin https://github.com/<你的账号>/<仓库名>.git
git push -u origin main
```

推上去后 **Actions → build-ios-ipa** 会自动跑（约 3–5 分钟）。公开仓库不消耗 Actions 额度。

### 2. 下载 ipa

两种方式，任选其一：

- **Releases（不用登录，最省事）**：打开 [Releases](../../releases/latest)，下载 `MusicHall-unsigned.ipa`。打 `v*` 标签时 CI 会自动把 ipa 附到 Release 上。
- **Actions Artifacts**：进那次运行 → 底部 **Artifacts** → 下载 `MusicHall-unsigned-ipa` → 解压得到 `MusicHall-unsigned.ipa`。注意 artifact 会压缩成 zip。

> 这个 ipa 是**未签名**的，不能直接装。下面用你自己的 Apple ID 签。

### 3. 在 Windows 上签名并安装

1. iPhone：**设置 → 隐私与安全性 → 开发者模式 → 打开**（iOS 16+ 必须先开，重启生效）
2. Windows 装 [Sideloadly](https://sideloadly.io/)，以及 iTunes 或「Apple Devices」应用（提供驱动）
3. 用数据线连 iPhone，Sideloadly 里拖入 `MusicHall-unsigned.ipa`，Apple ID 填你自己的（免费账号即可）
4. 点 Start，等它签名 + 安装
5. iPhone：**设置 → 通用 → VPN 与设备管理 → 信任** 你的开发者证书，然后打开 App

免费 Apple ID 的限制：**7 天**后失效、最多 3 个自签 App。到期用同样流程重签一次，App 里的登录态和队列不会丢（钥匙串数据跟着 App 走，重签覆盖安装即可保留）。

想自动续签可以用 AltStore（同一 Wi-Fi 下跑 AltServer）。

### 4. 有 Mac 的话

```bash
brew install xcodegen && xcodegen generate
open MusicHall.xcodeproj      # Xcode 里选自己的 Team，直接 Run 到真机
# 或者只出未签名 ipa：
./scripts/build-ipa.sh
```

> 工程用的是 Xcode 16 的「文件系统同步目录」格式（`objectVersion = 77`），需要 **Xcode 16 或更新**。
> 如果你手上是旧版 Xcode，直接 `brew install xcodegen && xcodegen generate` 按 `project.yml` 重新生成一份即可，
> CI 走的也是这条路径。

---

## 登录怎么走的

和桌面版一致，密码**不经过本应用**：

1. `POST`/`GET` 打开 `https://oauth-login.platform.hicloud.com/oauth2/v3/authorize`
   （`client_id=101444301`、`redirect_uri=hms://redirect_uri`、PKCE S256、`state` 单次）
2. 你在官方页面上扫码 / 短信 / 密码登录
3. 页面跳到 `hms://redirect_uri?code=…`，被 WebView 的导航拦截抓住 → 校验 `state`
4. `code` + `code_verifier` 换账号令牌 → `loginex` 换音乐会话令牌（`snsUserID` + `token`）
5. 音乐会话进钥匙串；业务请求带 `Authorization: Digest username=app-music-baseline, nonce=…, created=…, token=…`

几点必须知道的：

- **扫码需要第二台设备**：二维码显示在 iPhone 屏幕上，自己扫不到自己。单机建议用短信验证码或账号密码登录。
- **音乐令牌大约 7 天**，过期后接口返回授权错误，需要重新登录一次（标准 refresh 在上游已实测失败，本版不假装能自动续期）。
- `client_id` 不是为本项目注册的应用，是公开互操作资料里的第三方标识，可能随时失效。
- **必须直连华为 CDN**：开着代理/VPN 时音频请求会走代理，CDN 返 404，表现为「点了没反应、大部分歌播不了」。

---

## 工程结构

```
Config/Info.plist                  # 后台播放、深色、竖屏、启动色
project.yml                        # XcodeGen 配置（CI 用它生成工程）
MusicHall.xcodeproj                # 直接能开的工程（Xcode 16 同步目录格式）
scripts/build-ipa.sh               # macOS 本地出未签名 ipa
.github/workflows/ios-unsigned-ipa.yml
MusicHall/
├── App/
│   ├── MusicHallApp.swift         # 入口、外观（TabBar/导航栏压成近黑）
│   └── RootView.swift             # TabView + 迷你播放条 + 弹层
├── Core/
│   ├── OAuth.swift                # PKCE、回调校验、授权码/音乐会话兑换
│   ├── HTTP.swift                 # Digest 头、超时、只读重试、写入不重试
│   ├── MusicAPI.swift             # 搜索/收藏/歌单/历史/收藏状态/播放/历史上报
│   ├── Normalize.swift            # 松散 JSON → 模型（字段拼写兼容）
│   ├── Lyrics.swift               # LRC 解析 + 歌词地址/内嵌文本
│   ├── SafeURL.swift              # 音频/歌词只认华为 CDN 的 https 地址
│   ├── Keychain.swift             # 会话进钥匙串
│   ├── SessionStore.swift         # 登录态
│   ├── Settings.swift             # 音质/上报/播放模式落盘
│   └── Models.swift  JSON.swift  APIError.swift
├── Player/
│   └── PlayerEngine.swift         # AVPlayer、队列、四种模式、歌词、上报、锁屏
└── UI/                            # 全部界面（无 UI 框架，手写样式）
```

设计令牌集中在 `UI/Theme.swift`：`#0A0A0C` 底、`#141418` 卡片、`#F4F4F6` 主按钮、`#FF375F` 红心色。
颜色只留给封面与收藏，其余全是黑白灰 —— 与桌面版同一套关系。

---

## 已知限制

1. **登录页耦合**：官方页面在 `WKWebView` 里，只放行 `huawei.com` / `hicloud.com` / `dbankcloud.cn` 域名；华为若改登录链路，这里要跟着改。
2. **音乐令牌约 7 天**，无自动续期。
3. **音质以服务端返回为准**：界面只在「品质码 + 实际编码」都对得上时才显示「无损 FLAC / 标准 MP3」，其余显示为未知。
4. **特殊容器播不了**：极少数曲目返回非标准封装，AVPlayer 会失败并提示，不做解密兼容。
5. **接口随时可能变**：全部来自上游的抓包与兼容性实验，不做可用性承诺。
6. **没有歌单写操作**：本版只读歌单（创建/改名/删除仍请用官方客户端）。
7. **歌词取决于接口**：歌词地址来自播放解析响应的 `lyricAddress`（标准音质失败时会用无损重试一次）。曲目本身没歌词、或地址不在 `dbankcdn / tingmall / kuke` 白名单时，播放页会显示具体原因并可「重新加载」。

---

## 没有 Mac 时怎么自检

改完代码想知道有没有写崩，可以先用 tree-sitter 做一次 Swift 语法自检（不替代真正的编译，但能挡住括号、尾随闭包这类低级错误）：

```bash
cd tools/syntax-check && npm i && node check.js ../../MusicHall
# files=30 problems=0
```

真正的类型检查仍然只能在 macOS 上由 Xcode 完成（或推到 GitHub 让 Actions 跑）。

---

## 来源与许可

- 协议契约与界面结构参考：[Daydreamcgy/huawei-music-win](https://github.com/Daydreamcgy/huawei-music-win)（AGPL-3.0-only），其上游为 [talongao/huawei-music-desktop](https://github.com/talongao/huawei-music-desktop)
- 本项目自 2026-11-15 起把这些契约用 Swift 重写为 iOS 实现，并以 **AGPL-3.0-only** 授权：分发衍生作品（或通过网络提供服务）时必须同样以 AGPL-3.0 提供完整对应源码，并保留版权与许可声明，不提供任何担保。
- 许可证只覆盖本仓库的代码，不授予华为服务的接口使用权、音乐内容使用权，或「华为 / HUAWEI / 华为音乐」等名称与商标的使用权。

**本仓库及其产物与华为无任何关系。** 权利人如认为本项目涉及其合法权益，请通过 Issue 联系，维护者会核查并视情况调整或移除相关内容。以上不构成法律意见。
