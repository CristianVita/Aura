# Online metadata research

## What is feasible

[MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API) offers search and read-only lookup for recordings, artists, releases and release groups, including JSON results. A recording can occur on multiple releases, so a result can have multiple album and date candidates; the app should present candidates and provenance rather than silently asserting a single album or year. Text search needs sufficiently reliable existing title/artist metadata. A filename such as an automatically generated voice-message name is unlikely to provide a useful music query. Matching accuracy depends on the source data; a result is not proof of identity.

MusicBrainz requests require an identifying application User-Agent with contact information, and the public service asks clients to respect its [rate limit](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting), ordinarily no more than one request per second per IP. Non-commercial use is free according to the service; commercial use has separate terms. The implemented text search throttles requests, does not retry automatically or cache results, and runs only after an explicit user action. It sends the user-confirmed title and optional artist; it does not send server credentials, audio file paths or unrelated library contents. Display the data source and avoid changing audio tags or Navidrome server data.

For recordings with inadequate text metadata, [AcoustID](https://acoustid.org/webservice) can look up an audio fingerprint computed with Chromaprint and return MusicBrainz recording/release references. This needs an application API key, has its own rate limits and non-commercial-use restrictions, and needs native audio decoding/fingerprinting on Android and Windows. A fingerprint and duration are sent to the service; disclose this before lookup. Short messages, speech, edits and uncommon recordings may not match, and multiple candidates may exist. Never assume that all audio files are commercial music.

## Suggested future workflow

1. Offer an explicit per-track action and explain what information will be sent. No automatic bulk requests.
2. Prefer local/server metadata or IDs when available. Search MusicBrainz by title and artist when useful; offer a fingerprint approach only after separate integration and user approval.
3. Show candidates, release dates and sources, with the choice to cancel. Keep uncertain results separate from original metadata and apply them locally only on explicit confirmation. Preserve original data, backups and reversion.
4. Handle offline state, rate limiting, timeouts, no results, multiple releases and data licensing. Do not submit data to external services or write to any Navidrome instance as part of lookup.

This feasibility study preceded the implemented read-only text lookup; see `docs/online-metadata.md`. No fingerprint lookup or automatic application of results is implemented.

## Available release-year limitations

Android [MediaStore YEAR](https://developer.android.com/reference/android/provider/MediaStore.Audio.AudioColumns#YEAR) is an indexed tag whose meaning is described as the year the audio was recorded, and is not necessarily the original release date. Windows uses the year provided by its metadata reader; Navidrome provides the song or album year exposed by its API. Missing values stay unknown. A rescan or server refresh is needed for data cached before year support. [Navidrome's Subsonic compatibility](https://www.navidrome.org/docs/developers/subsonic-api/) does not make this client write metadata to the server.
