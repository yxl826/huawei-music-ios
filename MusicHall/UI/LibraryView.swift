import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageTitle(title: "我的", subtitle: "账号与你自己的音乐库")

                accountCard

                VStack(spacing: 0) {
                    NavigationLink {
                        FavoritesView()
                    } label: {
                        row(icon: "heart", title: "我的收藏", detail: "分页拉全后按歌曲去重计数")
                    }
                    divider
                    NavigationLink {
                        PlaylistsView()
                    } label: {
                        row(icon: "music.note.list", title: "我的歌单", detail: "自建与收藏的歌单")
                    }
                    divider
                    NavigationLink {
                        HistoryView()
                    } label: {
                        row(icon: "clock.arrow.circlepath", title: "播放历史", detail: "华为账号的播放记录")
                    }
                    divider
                    NavigationLink {
                        SettingsView()
                    } label: {
                        row(icon: "gearshape", title: "设置", detail: "音质、上报与账号")
                    }
                }
                .panel(radius: Theme.radiusXL)

                disclaimer
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .chromeScrollMargin()
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .overlay(alignment: .topTrailing) {
            TopActionBar()
                .padding(.trailing, Theme.pagePadding)
                .padding(.top, 2)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var accountCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Theme.surface2)
                Image(systemName: session.isAuthenticated ? "person.fill" : "person")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(session.isAuthenticated ? Theme.text : Theme.faint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.accountLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(session.expireLabel ?? (session.isAuthenticated ? "会话已保存在本机钥匙串" : "登录后同步你自己的音乐库"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)

            if session.isAuthenticated {
                Button {
                    session.logout()
                    player.clear()
                } label: {
                    Text("退出")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.surface2, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                PillButton(title: "登录", systemImage: "person.badge.key") {
                    nav.showLogin = true
                }
            }
        }
        .padding(14)
        .panel(radius: Theme.radiusXL)
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.leading, 52)
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("关于这个客户端")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text("非官方项目，与华为及其关联公司没有隶属或合作关系。只播放你账号里已有权益的内容，不提供音源、不下载、不绕过付费与地域限制。使用第三方客户端是否违反服务条款、账号是否受限，由使用者自行判断。")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var toast: ToastCenter

    @State private var showLogoutConfirm = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                section(title: "音质") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("音质", selection: $settings.settings.quality) {
                            ForEach(Quality.allCases) { quality in
                                Text(quality.label).tag(quality)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("无损需要账号本身有会员；实际输出以服务端返回的编码为准，界面只显示已确认的结果。")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .panel()
                }

                section(title: "播放") {
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "上报播放历史",
                            detail: "播放满 30 秒或半曲后上报一次，失败静默、不重试",
                            isOn: $settings.settings.syncHistory
                        )
                        divider
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("当前播放模式")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.text)
                                Text(player.mode.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.faint)
                            }
                            Spacer()
                            Image(systemName: player.mode.symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        divider
                        Button {
                            LyricsService.clearCache()
                            toast.show("已清除本机歌词缓存")
                        } label: {
                            HStack {
                                Text("清除歌词缓存")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text("内存缓存")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.faint)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .panel()
                }

                section(title: "账号") {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.accountLabel)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.text)
                                Text(session.expireLabel ?? "会话保存在钥匙串")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.faint)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        divider
                        Button {
                            if session.isAuthenticated {
                                showLogoutConfirm = true
                            } else {
                                // 未登录时这里只提示去登录页
                                toast.show("请先在「我的」页面登录")
                            }
                        } label: {
                            HStack {
                                Text("退出登录")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.like)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .panel()
                }

                section(title: "关于") {
                    VStack(alignment: .leading, spacing: 8) {
                        aboutRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        aboutRow("协议层", "参考 huawei-music-win 的接口契约重写")
                        aboutRow("许可", "AGPL-3.0-only")
                        Text("本应用不包含任何音源，也不提供下载、解密或离线导出。接口来自公开抓包与兼容性实验，可能随时失效。")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(14)
                    .panel()
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 14)
        }
        .chromeScrollMargin()
        .background(Theme.bg)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert("退出登录？", isPresented: $showLogoutConfirm) {
            Button("退出", role: .destructive) {
                session.logout()
                player.clear()
                toast.show("已退出登录")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机的会话凭据会被删除，播放队列也会清空。")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 2)
            content()
        }
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.like)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func aboutRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
        }
    }
}
