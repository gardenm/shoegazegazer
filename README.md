# shoegazegazer

A personal new-release digest that scores albums against a taste profile. Fetches recent releases from Album of the Year and MusicBrainz, enriches them with Last.fm tags, and ranks them by how closely they match your listening preferences.

## Setup

```
bundle install
```

Add your Last.fm API key to `.env`:

```
LASTFM_API_KEY=your_key_here
```

Get a free key at https://www.last.fm/api/account/create

## Usage

```
bundle exec bin/shoegazegazer                      # weekly digest, default profile
bundle exec bin/shoegazegazer --profile shoegaze   # use config/profiles/shoegaze.yml
bundle exec bin/shoegazegazer --all                # run every profile in config/profiles/
bundle exec bin/shoegazegazer --missed             # catch-up: last 12 months' high scorers
bundle exec bin/shoegazegazer --stats              # database stats for the current profile
```

## Profiles

One taste profile can't cover a whole record collection — a tag list broad
enough to catch both Whirr and Autechre matches everything and ranks nothing.
Instead, keep one focused profile per style you follow. Three starters live in
`config/profiles/` (edit them freely, or add your own):

| Profile | Flavour |
|---------|---------|
| `shoegaze` | Slowdive, MBV, dream pop, noise pop |
| `ambient_electronic` | Four Tet, Boards of Canada, IDM, drone |
| `post_rock` | Mogwai, Explosions in the Sky, instrumental builds |

`--profile NAME` picks one; `--all` runs the digest for each profile in turn.
Every profile keeps its own scores in the database (keyed by the config
file's basename), so an album can rank 85 for shoegaze and 20 for ambient
without either run clobbering the other.

## Persistence

Everything is stored in a SQLite database at `db/shoegazegazer.db`
(created automatically, gitignored; override the location with
`SHOEGAZEGAZER_DB=/path/to.db`):

- **albums** — every release ever seen, deduplicated on a normalised
  artist/title pair (case- and punctuation-insensitive). A rescrape never
  loses a known rating or URL.
- **album_scores** — one row per album *per profile*, with the full score
  breakdown and the Last.fm tags used. Scores are cached for 12 hours, so
  re-running the digest doesn't re-hit the Last.fm API.
- **scrape_runs** — a log of every scrape. Sources are only scraped once
  per day; later runs (including `--all`'s per-profile passes) reuse the
  day's catch.

### --missed

The weekly digest only looks at the last 14 days, so an album you didn't run
the tool for can slip past. `--missed` scores anything from the last 12
months that this profile hasn't rated yet, then shows the top 20 albums
scoring ≥ 50 that haven't been surfaced in the last 30 days.

## Web interface

```
bundle exec bin/shoegazegazer-web        # http://127.0.0.1:4567
```

A read-only browser for the score database — one tab per profile, each
showing the fresh digest (last 14 days) and the year's high scorers, plus a
stats page. It never scrapes or scores (so it needs no Last.fm key); refresh
the data with `bin/shoegazegazer --all` and reload.

There's also a JSON endpoint per profile for shortcuts/automations:
`GET /api/digest/:profile`.

### Feedback loop

Every album row has ▲/▼ buttons: *more like this* / *less like this*.
Ratings are stored per profile and feed back into scoring:

- artists you liked get **+12** on future albums; disliked artists get **−15**
- the tags of rated albums build a per-profile affinity — each net vote on a
  matching tag is worth ±1.5 points (capped at ±3 per tag, ±8 total)

Rating an album instantly re-ranks the whole profile from the stored score
components (no API calls), and the weekly/`--missed` runs apply the same
adjustment when scoring new albums. Click an active button again to clear
the rating.

Bind/port via env: `HOST=0.0.0.0 PORT=8080 bundle exec bin/shoegazegazer-web`.

## Run it like a Mac app

```
macos/install.sh
```

This installs two launchd agents:

- **com.shoegazegazer.web** keeps the web UI running at login
  (`PORT=8080 macos/install.sh` to change the port)
- **com.shoegazegazer.refresh** runs `--all` every Friday at 09:30 (New
  Music Friday) and posts a macOS notification when the digest is ready

Then open http://127.0.0.1:4567 in Safari and choose **File → Add to
Dock**: the app manifest gives it its own icon and a standalone window, so
it looks and behaves like a native app. Remove everything with
`macos/install.sh uninstall`; logs land in `/tmp/shoegazegazer-*.log`.

## Tests

```
bundle exec rake test
```

## How scoring works

Each album is scored out of 100 across three components:

| Component | Max | Logic |
|-----------|-----|-------|
| Artist match | 40 | 40 pts for direct match; up to 35 pts via Last.fm similarity chain |
| Tag match | 35 | Overlap between album/artist tags and your taste profile tags; capped at 5 matches |
| Metacritic score | 25 | Scaled linearly; unreviewed albums get 12 pts (neutral) |

Only albums with a Metacritic score ≥ 60 (or unscored) are considered. Results are sorted by taste score and the top 20 are shown.

## Taste profile

The taste profile lives in `config/taste_profile.yml` (gitignored so you can personalise it freely). On first run, copy the example:

```
cp config/taste_profile.yml.example config/taste_profile.yml
```

Then edit it:

```yaml
artists:
  - Slowdive
  - My Bloody Valentine
  - Beach House
  # ... add any artists whose similar-artists graph you want to draw from

tags:
  - shoegaze
  - dream pop
  - ambient
  # ... tags that describe your taste; up to 5 overlapping tags score full points

min_score: 60  # minimum AOTY/Metacritic score to include an album (0 to disable)
```

To use a different profile without replacing the default:

```
bundle exec bin/shoegazegazer --config path/to/other.yml
```

## Sources

| Source | Colour | Notes |
|--------|--------|-------|
| Album of the Year | cyan | Scrapes 4 pages of new releases; includes Metacritic scores |
| MusicBrainz | magenta | Public API, no auth required; 2 pages × 100 results |

Results from both sources are merged and deduplicated before scoring.

## Example output

```
⠋ Fetching new releases... ✔ done (198 AOTY + 106 MusicBrainz = 268 unique)
⠋ Scoring against your taste profile... ✔ done

┌──────┬───────────────────────────┬───────────────────────────────────────────────┬───────┬────────┬──────────────────────────────┬────────────┐
│ RANK │ ARTIST                    │ TITLE                                         │ SCORE │ SOURCE │ TAGS                         │ APPLE MU…  │
├──────┼───────────────────────────┼───────────────────────────────────────────────┼───────┼────────┼──────────────────────────────┼────────────┤
│ 1    │ Laurel Halo               │ Midnight Zone (Original Soundtrack to the Fi… │ 85.6  │ aoty   │ electronic, experimental, …  │ → 1        │
│ 2    │ Colleen                   │ Libres antes del final                        │ 74.8  │ aoty   │ ambient, experimental, ele…  │ → 2        │
│ 3    │ James Blake               │ Trying Times                                  │ 58.3  │ aoty   │ dubstep, electronic, exper…  │ → 3        │
│ 4    │ Clark                     │ Modal Stims                                   │ 54.6  │ aoty   │ idm, electronic, experimen…  │ → 4        │
│ 5    │ Sunday (1994)             │ Devotion [Deluxe]                             │ 54.3  │ aoty   │ indie pop, dream pop, elec…  │ → 5        │
│ 6    │ The Leaf Library          │ After The Rain, Strange Seeds                 │ 53.8  │ aoty   │ shoegaze, indie pop, dream…  │ → 6        │
│ 7    │ Xiu Xiu                   │ Xiu Mutha Fuckin' Xiu: Vol. 1 (Deluxe Editio… │ 53.8  │ aoty   │ experimental, electronic, …  │ → 7        │
│ 8    │ The Notwist               │ News From Planet Zombie                       │ 47.0  │ aoty   │ indie, electronic, german    │ → 8        │
│ 9    │ Sugar Plant               │ one dream, one star                           │ 46.3  │ aoty   │ dream pop, shoegaze, japan…  │ → 9        │
│ 10   │ Cashier                   │ The Weight                                    │ 45.8  │ aoty   │ shoegaze, indie rock, indie  │ → 10       │
│ 11   │ Girl Scout                │ Brink                                         │ 45.5  │ aoty   │ indie rock, psychedelic ro…  │ → 11       │
│ 12   │ Dylan Brady               │ Needle Guy                                    │ 44.8  │ aoty   │ hyperpop, electronic, nois…  │ → 12       │
│ 13   │ underscores               │ U                                             │ 42.5  │ aoty   │ electropop, dance-pop        │ → 13       │
│ 14   │ Grace Ives                │ Girlfriend                                    │ 41.8  │ aoty   │ electro, indie pop, art pop  │ → 14       │
│ 15   │ The Dear Hunter           │ Sunya                                         │ 41.0  │ aoty   │ progressive rock, experime…  │ → 15       │
│ 16   │ Masahiro Takahashi        │ In Another                                    │ 41.0  │ aoty   │ ambient, japanese, jazz      │ → 16       │
│ 17   │ Damaged Bug               │ ZUZAX                                         │ 41.0  │ aoty   │ electronic, psychedelic, i…  │ → 17       │
│ 18   │ Green-House               │ Hinterlands                                   │ 39.8  │ aoty   │ ambient, new age, electronic │ → 18       │
│ 19   │ The Orielles              │ Only You Left                                 │ 39.8  │ aoty   │ dream pop, indie rock, ind…  │ → 19       │
│ 20   │ ladylike                  │ It's a Pleasure of Mine, to Know You're Fine  │ 39.8  │ aoty   │ indie rock, power pop, sho…  │ → 20       │
└──────┴───────────────────────────┴───────────────────────────────────────────────┴───────┴────────┴──────────────────────────────┴────────────┘

Apple Music links:
  1. https://music.apple.com/search?term=Laurel+Halo+Midnight+Zone+...
  2. https://music.apple.com/search?term=Colleen+Libres+antes+del+final
  ...

Powered by Last.fm • Album of the Year • MusicBrainz • Sunday, March 22 2026
```

Scores and source colours are rendered in colour in a real terminal (green ≥ 70, yellow ≥ 50, red < 50; cyan = AOTY, magenta = MusicBrainz).
