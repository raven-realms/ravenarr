# Ravenarr

An unofficial, open-source iOS client for [Overseerr](https://overseerr.dev) and
[Jellyseerr](https://github.com/Fallenbagel/jellyseerr). Point it at your own
server — nothing is hardcoded — sign in with Plex, Jellyfin/Emby, or a local
account, and do everything you can do in the web UI from your phone.

Not affiliated with, endorsed by, or sponsored by Overseerr, Jellyseerr, Plex,
or Jellyfin. "Ravenarr" is not a reference to any of their trademarks.

## Features

- **Bring your own server** — enter any Overseerr/Jellyseerr URL on first
  launch; validated live against `/api/v1/status`. Supports self-signed
  certificates (opt-in).
- **Three sign-in methods** — Plex (PIN-based OAuth, no URL scheme needed),
  Jellyfin/Emby, or a server's local account.
- **Discover** — trending movies/TV, your Plex watchlist, search, and
  collections (request every unrequested movie in a collection at once).
- **Requests** — season picker and 4K toggle at request time; approve/decline
  for admins; re-route an existing request to a different Radarr/Sonarr
  server, quality profile, or root folder (e.g. a "Kids" library).
- **Issues** — track and resolve Seerr's media issue reports.
- **Multi-server** — save more than one server and switch between them.
- **Push notifications** — client-side is done (permission + APNs device
  token + a configurable relay URL); you still need to run the relay
  described below.

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. `xcodegen generate` — produces `Ravenarr.xcodeproj` (gitignored, fully
   regenerable from `project.yml`, so just re-run this after pulling changes
   that touch new files).
3. Open `Ravenarr.xcodeproj`, set your team under Signing & Capabilities, hit
   ⌘R.

## Push notifications — what the relay needs to do

Seerr has no concept of APNs. This app registers a device token to a relay
*you* host; see [`Ravenarr/Networking/PushRelayClient.swift`](Ravenarr/Networking/PushRelayClient.swift)
for the exact contract: a `POST /devices` endpoint storing `seerrUserId ->
[deviceToken, ...]` (one-to-many — a user may have multiple devices), and a
webhook receiver you point Seerr's Webhook notification agent at. For
`MEDIA_APPROVED`/`MEDIA_AVAILABLE` events, Seerr's payload's `notifyuser.id`
is the original requester (not the admin who approved it) — look up every
token stored for that id and push to each via APNs using your own `.p8` key.

## Known gaps

- No dedicated iPad-optimized layout yet (it runs, just not adaptive).
- No tags support on requests.
- Push only works once you've built and deployed the relay above.
- Auto-routing requests to a "Kids" vs. "Adult" library by content rating is
  a deliberate non-goal of this app — that belongs in your Radarr/Sonarr/Seerr
  server config, not the client.

## License

MIT — see [LICENSE](LICENSE).
