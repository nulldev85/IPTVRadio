import Foundation
@testable import IPTVRadio

/// Embedded test fixtures. No real provider data, no credentials.
enum Fixtures {
    static let authResponseJSON = """
    {
      "user_info": {
        "username": "testuser",
        "password": "testpass",
        "auth": 1,
        "status": "Active",
        "exp_date": "4102444800",
        "is_trial": "0",
        "active_cons": "1",
        "max_connections": "2"
      },
      "server_info": {
        "url": "provider.example.net",
        "port": "80",
        "https_port": "443",
        "server_protocol": "https",
        "timezone": "America/New_York"
      }
    }
    """

    static let authRejectedJSON = """
    {
      "user_info": { "auth": 0, "status": "Disabled", "username": "testuser" },
      "server_info": { "url": "provider.example.net", "port": "80" }
    }
    """

    static let authExpiredJSON = """
    {
      "user_info": { "auth": 1, "status": "Active", "exp_date": "1000000000" },
      "server_info": { "url": "provider.example.net", "port": "80" }
    }
    """

    static let categoriesJSON = """
    [
      { "category_id": "1", "category_name": "SiriusXM", "parent_id": 0 },
      { "category_id": "2", "category_name": "Music Radio", "parent_id": 0 },
      { "category_id": "3", "category_name": "Movies", "parent_id": 0 },
      { "category_id": "4", "category_name": "Talk Radio", "parent_id": 0 }
    ]
    """

    static let liveStreamsJSON = """
    [
      { "num": 1, "name": "SiriusXM Hits 1", "stream_type": "live", "stream_id": "8020", "stream_icon": "https://logo.example/hits1.png", "epg_channel_id": "sxm-hits1", "category_id": "1", "direct_source": "" },
      { "num": 2, "name": "SiriusXM Octane", "stream_type": "live", "stream_id": "8021", "stream_icon": null, "epg_channel_id": null, "category_id": "1", "direct_source": "" },
      { "num": 3, "name": "Jazz Cafe Radio", "stream_type": "live", "stream_id": "9002", "stream_icon": "", "epg_channel_id": "", "category_id": "2", "direct_source": "" },
      { "num": 4, "name": "News Talk 101", "stream_type": "live", "stream_id": "9004", "stream_icon": null, "epg_channel_id": null, "category_id": "4", "direct_source": "" },
      { "num": 5, "name": "Action Movies HD", "stream_type": "live", "stream_id": "5001", "stream_icon": null, "epg_channel_id": null, "category_id": "3", "direct_source": "" },
      { "num": 6, "name": "SXM Faction Talk", "stream_type": "radio", "stream_id": "8023", "stream_icon": null, "epg_channel_id": "sxm-faction", "category_id": "1", "direct_source": "http://edge.example.net:8042/radio/faction.m3u8" }
    ]
    """

    static let playlistText = """
    #EXTM3U
    #EXTINF:-1 tvg-id="sxm-hits1" tvg-logo="https://logo.example/hits1.png" group-title="SiriusXM",SiriusXM Hits 1
    https://edge.example.net:8042/live/8020.m3u8
    #EXTINF:-1 group-title="SiriusXM",SiriusXM Octane
    https://edge.example.net:8042/live/8021.m3u8
    #EXTINF:-1 group-title="Music Radio",Jazz Cafe Radio
    https://edge.example.net:8042/live/9002.mp3
    #EXTINF:-1 group-title="Movies",Blockbuster Cinema HD
    https://edge.example.net:8042/live/5001.mkv
    #EXTGRP:Talk Radio
    #EXTINF:-1,News Talk 101 AM
    https://edge.example.net:8042/live/9004.mp3
    #EXTINF:-1 group-title="Music Radio",Smooth Jazz 24/7, the best mix
    https://edge.example.net:8042/live/9007.aac
    """

    static let malformedPlaylistText = """
    #EXTM3U
    #EXTINF:-1 no url after this
    #EXTINF:garbage garbage
    not-a-url-at-all
    #EXTINF:-1 group-title="Music Radio",Still Valid
    https://edge.example.net:8042/live/9010.mp3
    """

    static let emptyPlaylistText = "#EXTM3U\n"

    /// Builds a playlist with N entries for large-playlist tests.
    static func largePlaylist(entryCount: Int) -> String {
        var text = "#EXTM3U\n"
        for index in 0..<entryCount {
            text += "#EXTINF:-1 group-title=\"Music Radio\",Test Station \(index)\n"
            text += "https://edge.example.net:8042/live/\(10_000 + index).mp3\n"
        }
        return text
    }

    static func makeCredentials() -> XtreamCredentials {
        XtreamCredentials(serverInput: "https://provider.example.net:8080", username: "testuser", password: "testpass")
    }
}
