# Offline downloads

Individual Navidrome tracks can be downloaded from the track's long-press menu. Settings → Offline files lists downloaded tracks and allows playback or removal. Downloads are private to Aura. General offline settings choose Wi-Fi only (default) or allow other networks including mobile data; keep Aura open until a download finishes. A track is limited to 512 MB. An album can also be downloaded from its album page. The confirmation states the number of Navidrome tracks and includes tracks hidden by filters; album groups currently use the album name, so identical names from different sources are grouped together. Local tracks are excluded. Downloads run sequentially while the dialog remains open. Cancel stops after the current track; completed copies remain. Failures are counted and retrying skips verified copies. Remove copies individually in Settings → Offline files. There is no automatic streaming cache or background scheduler yet.

Downloads are verified using their size and SHA-256 before playback. A damaged downloaded copy produces an error rather than silently streaming. Metadata retained with a download allows it to remain visible after its server account is removed. Removing a downloaded track currently in the playback queue is blocked.

Automated tests cover downloads, integrity checks and playback selection with simulated server responses. Android playback was also verified in a separate test app with synthetic audio. Individual offline playback was previously confirmed with a real Navidrome server. Album downloads have automated tests using synthetic tracks; the complete album flow has not been tested against a real server.

The Offline files screen includes the current player and a seek slider for adjusting playback position.


## Download network policy

Settings → Offline, cache and downloads → General controls downloads, not streaming or artwork requests. Wi-Fi only is the default; Wi-Fi and mobile data also allows Ethernet and other networks. The preference is stored locally and is not included in Aura backups. On Wi-Fi-only mode, the app checks the reported network before a download and listens for changes, aborting the current transfer if it becomes disallowed. Incomplete files are cleaned up and completed downloads remain. No automatic resume is scheduled; retry manually. A VPN, ambiguous or mixed network may be blocked conservatively. The OS can report changes after the actual handover, so this is not an absolute guarantee of zero cellular traffic during a transition. A Wi-Fi hotspot can itself use cellular data. Automated tests use simulated connectivity and streams; physical Wi-Fi/mobile handover has not been tested.

## Media storage overview

Settings → Offline, cache and downloads → Media shows a count and size for registered audio copies whose file exists and matches the recorded size. This quick overview does not check file hashes; the existing playback flow verifies each file before use. The total excludes cover images, temporary files and unregistered files, so it is not a complete measurement of disk space used by Aura. The button opens Offline files, where copies can be played or removed individually. No cleanup or deletion runs when viewing the overview.

## Temporary image cache

Settings → Offline, cache and downloads → Images displays the number of entries and encoded bytes in Aura's bounded in-memory source artwork cache. Entries can include pending or unsuccessful requests, and this figure is not the total memory used by decoded images, the widgets showing them, or custom album cover storage. Clearing it drops only these temporary cache references; existing displayed images or in-flight requests can remain in memory, and artwork may be fetched again over the current connection. The operation does not delete custom album cover files, downloaded audio, local audio metadata or images from Navidrome. The custom cover store and its backup are separate.

## Playlist downloads

A saved playlist can download its available Navidrome tracks after confirmation. Duplicate references are processed once; local and unavailable tracks are excluded. The existing download network policy, sequential progress, cancellation after the current track, and individual offline-file management apply. Keep Aura open during the operation. Playlist downloads have been tested with synthetic tracks; a real-server playlist download has not been verified.

## Artist and genre downloads

Artist and genre pages can download matching Navidrome tracks after confirmation. Matching follows the library's exact group names, and includes matching tracks hidden by rating filters and tracks from different sources. Local tracks are excluded. The existing sequential transfer, network policy, progress and cancellation rules apply. Synthetic widget tests cover the actions; real artist and genre downloads have not been tested.

## Automatic playback cache

Media settings offer an optional automatic Navidrome playback cache, off by default. It stores audio separately from explicit downloads, up to 2 GB of audio data; small bookkeeping files are additional. Entries are keyed by a hash of the logical track URI, checked with SHA-256 before use, and the oldest unused completed entries are evicted when new space is needed. Files being read or written are not evicted. Downloaded manual copies take precedence. The cache setting and files are device-local and are not included in Aura backups; turning the setting off stops cache use but does not erase existing entries.

The source stores a track only when an entire response of known size is received during playback. Partial range responses, interrupted playback, unknown sizes, unsupported media types and tracks larger than the quota are not retained. Seeking may prevent caching. Streaming uses the current playback connection, including mobile data; the download-only network setting does not apply. Existing queued tracks begin using the option when a queue is rebuilt. Cache and normal playback use just_audio's experimental stream-source API and a local loopback proxy, with Android cleartext restricted to 127.0.0.1. Tests cover the quota, integrity, cancellation, saved setting and priority of manual downloads. Silent synthetic WAV playback and a cache hit were verified with the native Windows player and in an Android test APK whose ID was checked as `.integration`; real Navidrome playback, physical network transitions and long-running use have not been verified. In particular, some servers or audio decoders may use ranges that do not produce a cacheable full response.

Media settings also offer confirmed clearing of this temporary audio cache. Entries actively read or written are skipped; manual downloads are unaffected. A process lock prevents another Aura instance from managing the same cache simultaneously. If it is already locked or storage is unavailable, that instance streams normally and displays the cache as unavailable.
