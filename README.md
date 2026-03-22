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
bundle exec bin/shoegazegazer
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
