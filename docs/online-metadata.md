# Online song information

From a track's details, choose the MusicBrainz lookup action. Review or edit the title and optional artist, then press Search. Until that action, the screen makes no lookup request. Auto-generated filenames such as AUD- names usually need a descriptive title to find useful results.

The request sends the entered title and optional artist to MusicBrainz over HTTPS. As with any internet request, the provider receives the IP address. It does not send audio, file paths, Navidrome addresses or credentials. Search results are informational and are not automatically applied, cached or saved; this feature does not write to audio files or any Navidrome server. Each candidate can refer to multiple releases and is not proof of a match.

The first version displays up to ten candidates and up to six releases per candidate, when available. It shows a message for no results, connection errors and rate limiting. Requests are serialized, spaced at least 1.1 seconds apart, and never automatically retried. Audio fingerprint identification and application of results are not implemented.

MusicBrainz service documentation: [search](https://musicbrainz.org/doc/MusicBrainz_API/Search), [rate limits](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting). Its public service has separate terms for commercial use.
