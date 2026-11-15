import Foundation

/// 响应归一化：接口字段拼写不统一（contentID / contentId / songCode），这里逐个兜。
enum Normalize {
    static func artists(_ value: JSON) -> [ArtistRef] {
        let pairs = JSONValue.objects(value["artistNamePairs"])
        var result: [ArtistRef] = pairs.compactMap { pair in
            guard let name = JSONValue.text(pair["artistName"]) ?? JSONValue.text(pair["name"]) else {
                return nil
            }
            return ArtistRef(id: JSONValue.text(pair["artistID"]) ?? JSONValue.text(pair["id"]), name: name)
        }
        if result.isEmpty {
            let fallback = JSONValue.text(value["artistName"]) ?? JSONValue.text(value["singerName"])
            let ids = JSONValue.list(value["artistID"]).compactMap { $0 as? String }.filter { !$0.isEmpty }
            if let fallback, !fallback.isEmpty {
                // 不按逗号切分歌手串，宁可整串显示，也不丢艺名信息。
                result.append(ArtistRef(id: ids.count == 1 ? ids[0] : nil, name: fallback))
            }
        }
        return result
    }

    static func cover(_ value: JSON) -> String? {
        let picture = JSONValue.dict(value["picture"])
        let candidates = [
            picture["bigImgURL"], picture["middleImgURL"], picture["smallImgURL"],
            value["coverUrl"], value["cover"]
        ]
        for candidate in candidates {
            let text = JSONValue.text(candidate)
            if SafeURL.isSafe(text) {
                return text
            }
        }
        return nil
    }

    static func track(_ value: Any?) -> Track? {
        let json = JSONValue.dict(value)
        guard let id = JSONValue.text(json["contentID"])
            ?? JSONValue.text(json["contentId"])
            ?? JSONValue.text(json["songCode"]),
            let title = JSONValue.text(json["contentName"]) ?? JSONValue.text(json["songName"])
        else { return nil }

        let albumPair = JSONValue.dict(json["albumNamePair"])
        let albumId = JSONValue.text(json["albumID"])
            ?? JSONValue.text(json["albumId"])
            ?? JSONValue.text(albumPair["id"])
            ?? JSONValue.text(albumPair["albumID"])
        let albumTitle = JSONValue.text(json["albumName"])
            ?? JSONValue.text(albumPair["name"])
            ?? JSONValue.text(albumPair["albumName"])

        var album: AlbumRef?
        if let albumId, let albumTitle {
            album = AlbumRef(id: albumId, title: albumTitle)
        }

        return Track(
            id: id,
            title: title,
            artists: artists(json),
            album: album,
            coverUrl: cover(json),
            durationSeconds: JSONValue.number(json["duration"]),
            available: true
        )
    }

    static func tracks(_ value: Any?) -> [Track] {
        JSONValue.list(value).compactMap { track($0) }
    }

    static func playlist(_ value: Any?) -> Playlist? {
        let json = JSONValue.dict(value)
        guard let id = JSONValue.text(json["contentID"])
            ?? JSONValue.text(json["contentId"])
            ?? JSONValue.text(json["musicListID"]),
            let title = JSONValue.text(json["contentName"]) ?? JSONValue.text(json["name"])
        else { return nil }

        let kind = PlaylistKind(rawValue: kindName(for: JSONValue.contentType(json["contentType"])) ?? "") ?? .unknown
        let description = JSONValue.text(json["listDesc"]) ?? JSONValue.text(json["description"])
        return Playlist(
            id: id,
            title: title,
            coverUrl: cover(json),
            count: JSONValue.number(json["totalCount"])
                ?? JSONValue.number(json["songCount"])
                ?? JSONValue.number(json["count"]),
            kind: kind,
            description: description
        )
    }

    private static func kindName(for contentType: String?) -> String? {
        switch contentType {
        case "4": return PlaylistKind.collected.rawValue
        case "5": return PlaylistKind.owned.rawValue
        case "7": return PlaylistKind.chart.rawValue
        default: return nil
        }
    }

    /// 发现接口把歌曲和各类歌单混在一页里，先剔掉歌曲再按「类型:ID」去重。
    static func playlists(fromLibraryEntries entries: [JSON]) -> [Playlist] {
        var seen = Set<String>()
        var result: [Playlist] = []
        for entry in entries {
            let type = JSONValue.contentType(entry["contentType"])
            if type == "1" { continue }
            let rawId = JSONValue.text(entry["contentID"])
                ?? JSONValue.text(entry["contentId"])
                ?? JSONValue.text(entry["musicListID"])
                ?? ""
            let key = "\(type ?? ""):\(rawId)"
            if seen.contains(key) { continue }
            seen.insert(key)
            if let playlist = playlist(entry) {
                result.append(playlist)
            }
        }
        return result
    }

    static func playlistDetail(_ response: JSON) -> (Playlist?, [Track], Int) {
        let detail = JSONValue.dict(response["playListInfoEx"])
        var info = JSONValue.dict(detail["playListInfo"])
        info["contentType"] = "5"
        let songs = JSONValue.list(detail["playListSongInfoList"])
        return (playlist(info), tracks(songs), songs.count)
    }

    static func publicPlaylistDetail(_ response: JSON) -> (Playlist?, [Track], Int) {
        let detail = JSONValue.dict(response["musicListInfoEx"])
        var info = JSONValue.dict(detail["musicListDetail"])
        if info["contentType"] == nil {
            info["contentType"] = "4"
        }
        let songs = JSONValue.list(detail["songSimpleInfos"])
        return (playlist(info), tracks(songs), songs.count)
    }

    static func searchPage(_ response: JSON) -> (tracks: [Track], total: Double?, hasMore: Bool) {
        let songs = JSONValue.list(response["songSimpleInfos"])
        let hasMore = (JSONValue.contentType(response["hasNextPage"]) ?? "0") == "1"
        return (tracks(songs), JSONValue.number(response["totalNum"]), hasMore)
    }

    static func history(_ response: JSON) -> [Track] {
        tracks(response["contentSimpleInfos"])
    }

    /// 只有「品质码 + 实际编码」都对得上才宣称无损，其余一律 unknown。
    static func confirmedQuality(_ playQuality: Any?, _ contentType: Any?) -> String {
        let quality = JSONValue.contentType(playQuality) ?? ""
        let codec = (JSONValue.text(contentType) ?? "").lowercased()
        let isFLAC = codec.contains("flac")
        let isMP3 = codec.contains("mp3") || codec == "audio/mpeg"
        if quality == "3", isFLAC { return Quality.lossless.rawValue }
        if quality == "1", isMP3 { return Quality.standard.rawValue }
        return "unknown"
    }
}
