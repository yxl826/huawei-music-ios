import Foundation

/// 业务接口封装。写入类请求一律不自动重试：超时也可能已经在服务端生效。
final class MusicAPI {
    static let shared = MusicAPI()
    private init() {}

    /// 由会话层维护，登录/登出时同步更新。
    var session: MusicSession?

    // MARK: - 会话前置校验

    private func requireToken() throws -> String {
        guard let token = session?.token, !token.isEmpty else { throw APIError.needsLogin }
        return token
    }

    private func requireSnsUserID() throws -> String {
        _ = try requireToken()
        guard let sns = session?.snsUserID, !sns.isEmpty else {
            throw APIError.invalid("音乐会话缺少用户标识，请重新登录")
        }
        return sns
    }

    private func validId(_ value: String, _ label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { throw APIError.invalid("\(label)无效") }
        return trimmed
    }

    // MARK: - 搜索

    func search(query: String, start: Int = 0, limit: Int = 20) async throws -> PagedTracks {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { throw APIError.invalid("搜索词不能为空") }
        let response = try await Transport.post(
            path: "/music-search-service/v10/service/fuzzysearch",
            body: [
                "contentType": "1",
                "correct": "1",
                "queryWord": String(word.prefix(80)),
                "start": String(start),
                "limit": String(limit)
            ],
            token: nil,
            stage: "搜索"
        )
        let page = Normalize.searchPage(response)
        return PagedTracks(
            tracks: page.tracks,
            nextStart: start + limit,
            hasMore: page.hasMore,
            total: page.total
        )
    }

    // MARK: - 收藏

    func favorites(start: Int = 0, limit: Int = 50) async throws -> (entries: [JSON], tracks: [Track], hasMore: Bool) {
        let sns = try requireSnsUserID()
        let token = try requireToken()
        let response = try await Transport.post(
            path: "/music-userbehavior-service/v3/service/favorite/simple/all",
            body: [
                "targetSnsUserID": sns,
                "start": start,
                "limit": limit,
                "contentTypes": ["1"]
            ],
            token: token,
            stage: "读取收藏"
        )
        let entries = JSONValue.objects(response["favoriteInfos"])
        return (entries, Normalize.tracks(response["favoriteInfos"]), entries.count == limit)
    }

    /// 一个请求形状同时发现歌曲与各类个人歌单（contentTypes 1/4/5/7）。
    func library(start: Int = 0, limit: Int = 200) async throws -> [JSON] {
        let sns = try requireSnsUserID()
        let token = try requireToken()
        let response = try await Transport.post(
            path: "/music-userbehavior-service/v3/service/favorite/simple/all",
            body: [
                "targetSnsUserID": sns,
                "start": start,
                "limit": limit,
                "contentTypes": ["1", "4", "5", "7"]
            ],
            token: token,
            stage: "读取歌单"
        )
        return JSONValue.objects(response["favoriteInfos"])
    }

    /// 翻页直到短页 / 无进展 / 达到保守上限，再只留歌单。
    func discoverPlaylists() async throws -> PagedPlaylists {
        let pageLimit = 200
        let pageCap = 10
        var entries: [JSON] = []
        var seen = Set<String>()
        var start = 0
        var truncated = true
        for _ in 0..<pageCap {
            let page = try await library(start: start, limit: pageLimit)
            var fresh = 0
            for item in page {
                let type = JSONValue.contentType(item["contentType"]) ?? ""
                let rawId = JSONValue.text(item["contentID"])
                    ?? JSONValue.text(item["contentId"])
                    ?? JSONValue.text(item["musicListID"])
                    ?? ""
                guard !rawId.isEmpty else { continue }
                let key = "\(type):\(rawId)"
                if seen.contains(key) { continue }
                seen.insert(key)
                fresh += 1
                entries.append(item)
            }
            start += pageLimit
            if page.count < pageLimit || fresh == 0 {
                truncated = false
                break
            }
        }
        return PagedPlaylists(playlists: Normalize.playlists(fromLibraryEntries: entries), truncated: truncated)
    }

    // MARK: - 歌单详情

    func playlistDetail(id: String, start: Int = 0, limit: Int = 50) async throws -> (Playlist?, [Track], Int) {
        let token = try requireToken()
        let playListID = try validId(id, "歌单 ID")
        let response = try await Transport.get(
            path: "/music-userbehavior-service/v1/service/playlist/detail/all",
            query: ["playListID": playListID, "start": String(start), "limit": String(limit)],
            token: token,
            stage: "读取歌单"
        )
        return Normalize.playlistDetail(response)
    }

    func publicPlaylist(id: String, start: Int = 0, limit: Int = 50) async throws -> (Playlist?, [Track], Int) {
        let musicListID = try validId(id, "歌单 ID")
        let response = try await Transport.post(
            path: "/music-operation-service/v2/service/musiclist/detail/bymusiclistid",
            body: ["musicListID": musicListID, "copyrightSwitch": "1", "start": start, "limit": String(limit)],
            token: nil,
            stage: "读取歌单"
        )
        return Normalize.publicPlaylistDetail(response)
    }

    // MARK: - 播放历史

    func recent() async throws -> [Track] {
        let token = try requireToken()
        let response = try await Transport.get(
            path: "/music-userbehavior-service/v1/service/recentlyplayed/query",
            query: ["contentType": "1"],
            token: token,
            stage: "读取播放历史"
        )
        return Normalize.history(response)
    }

    // MARK: - 收藏状态

    func favoriteExist(_ trackId: String) async throws -> Bool {
        let token = try requireToken()
        let id = try validId(trackId, "歌曲 ID")
        let response = try await Transport.get(
            path: "/music-userbehavior-service/v1/service/favorite/simple/exist",
            query: ["contentType": "1", "contentID": id],
            token: token,
            stage: "查询收藏状态"
        )
        guard let exist = JSONValue.contentType(response["exist"]), ["0", "1"].contains(exist) else {
            throw APIError.invalid("服务端未确认收藏状态")
        }
        return exist == "1"
    }

    @discardableResult
    func setFavorite(_ trackId: String, favorite: Bool) async throws -> Bool {
        let token = try requireToken()
        let id = try validId(trackId, "歌曲 ID")
        _ = try await Transport.post(
            path: "/music-userbehavior-service/v1/service/favorite/\(favorite ? "create" : "delete")",
            body: ["contentType": "1", "contentID": id],
            token: token,
            stage: favorite ? "收藏" : "取消收藏",
            retry: false
        )
        return favorite
    }

    // MARK: - 播放

    func playbackResponse(trackId: String, quality: Quality) async throws -> JSON {
        let token = try requireToken()
        let id = try validId(trackId, "歌曲 ID")
        return try await Transport.post(
            path: "/music-play-service/v3/service/file/bycontentcode",
            body: ["contentCode": id, "contentType": "1", "qualityType": quality.apiValue],
            token: token,
            stage: "解析播放地址"
        )
    }

    func resolvePlayback(trackId: String, quality: Quality) async throws -> PlaybackInfo {
        let response = try await playbackResponse(trackId: trackId, quality: quality)
        let fileURL = JSONValue.text(response["fileURL"])
        guard let url = SafeURL.url(fileURL) else {
            throw APIError.invalid("服务端未返回可播放的音频地址")
        }
        return PlaybackInfo(
            url: url,
            actualQuality: Normalize.confirmedQuality(response["playQuality"] ?? response["qualityType"], response["type"]),
            contentType: JSONValue.text(response["type"]),
            durationSeconds: JSONValue.number(JSONValue.dict(response["songInfo"])["duration"])
        )
    }

    /// 只在真实听到足够时长后上报一次，duration 用实际收听秒数，不拿整曲时长冒充。
    func reportPlayback(track: Track, listenedSeconds: Double) async throws {
        let token = try requireToken()
        let duration = max(0, Int(listenedSeconds.rounded(.down)))
        guard duration > 0 else { return }
        var entry: JSON = [
            "songCode": track.id,
            "contentCode": track.id,
            "contentType": "1",
            "songName": track.title,
            "listenType": "1",
            "duration": duration,
            "createTime": JSONValue.timestamp14(),
            "playCount": 1
        ]
        if let songDuration = track.durationSeconds, songDuration > 0 {
            entry["songDuration"] = Int(songDuration.rounded(.up))
        }
        _ = try await Transport.post(
            path: "/music-userbehavior-service/v1/service/recentlyplayed/create",
            body: ["createRecentPlayInfos": [entry]],
            token: token,
            stage: "播放历史上报",
            retry: false
        )
    }
}
