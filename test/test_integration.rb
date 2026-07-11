# frozen_string_literal: true

require_relative 'test_helper'

# ---------------------------------------------------------------------------
# Tests for the --missed query logic
# ---------------------------------------------------------------------------
class TestMissedQuery < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
    @profile = 'taste_profile'
    @cutoff_12mo = Date.today - 365
  end

  def test_finds_high_scoring_albums_from_last_12_months
    album = insert_album!(@db, artist: 'Slowdive', title: 'A',
                               release_date: Date.today - 60)
    # Score > 50, scored long ago (not recently surfaced)
    insert_score!(@db, album_id: album[:id], similarity: 75.0,
                       scored_at: Time.now - (60 * 86_400))

    results = missed_query(run_start: Time.now)
    assert_equal 1, results.size
    assert_equal 'Slowdive', results.first[:artist]
  end

  def test_excludes_albums_scored_below_threshold
    album = insert_album!(@db, artist: 'Low Scorer', title: 'Meh',
                               release_date: Date.today - 60)
    insert_score!(@db, album_id: album[:id], similarity: 40.0,
                       scored_at: Time.now - (60 * 86_400))

    results = missed_query(run_start: Time.now)
    assert_empty results
  end

  def test_excludes_albums_older_than_12_months
    album = insert_album!(@db, artist: 'Old Band', title: 'Ancient',
                               release_date: Date.today - 400)
    insert_score!(@db, album_id: album[:id], similarity: 90.0,
                       scored_at: Time.now - (60 * 86_400))

    results = missed_query(run_start: Time.now)
    assert_empty results
  end

  def test_excludes_recently_surfaced_albums
    album = insert_album!(@db, artist: 'Recent', title: 'Just Seen',
                               release_date: Date.today - 10)
    # Scored 5 days ago — within the 30-day "recently surfaced" window
    insert_score!(@db, album_id: album[:id], similarity: 80.0,
                       scored_at: Time.now - (5 * 86_400))

    results = missed_query(run_start: Time.now)
    assert_empty results
  end

  def test_includes_newly_scored_albums_from_this_run
    album = insert_album!(@db, artist: 'New Find', title: 'Discovery',
                               release_date: Date.today - 90)
    run_start = Time.now
    # Scored AFTER run_start — simulates scoring during the --missed run
    insert_score!(@db, album_id: album[:id], similarity: 65.0,
                       scored_at: run_start + 1)

    results = missed_query(run_start: run_start)
    assert_equal 1, results.size
    assert_equal 'New Find', results.first[:artist]
  end

  def test_results_ordered_by_similarity_score_descending
    a1 = insert_album!(@db, artist: 'Band A', title: 'X', release_date: Date.today - 60)
    a2 = insert_album!(@db, artist: 'Band B', title: 'Y', release_date: Date.today - 60)
    a3 = insert_album!(@db, artist: 'Band C', title: 'Z', release_date: Date.today - 60)

    insert_score!(@db, album_id: a1[:id], similarity: 60.0, scored_at: Time.now - (60 * 86_400))
    insert_score!(@db, album_id: a2[:id], similarity: 90.0, scored_at: Time.now - (60 * 86_400))
    insert_score!(@db, album_id: a3[:id], similarity: 75.0, scored_at: Time.now - (60 * 86_400))

    results = missed_query(run_start: Time.now)
    scores = results.map { |r| r[:similarity_score] }
    assert_equal [90.0, 75.0, 60.0], scores
  end

  def test_limits_to_20_results
    25.times do |i|
      a = insert_album!(@db, artist: "Band #{i}", title: "Album #{i}",
                             release_date: Date.today - 60)
      insert_score!(@db, album_id: a[:id], similarity: 50.0 + i,
                         scored_at: Time.now - (60 * 86_400))
    end

    results = missed_query(run_start: Time.now)
    assert_equal 20, results.size
  end

  def test_filters_by_profile_name
    album = insert_album!(@db, artist: 'Slowdive', title: 'A',
                               release_date: Date.today - 60)
    # Score under a different profile
    insert_score!(@db, album_id: album[:id], profile: 'other_profile',
                       similarity: 80.0, scored_at: Time.now - (60 * 86_400))

    results = missed_query(run_start: Time.now)
    assert_empty results
  end

  private

  # Replicate the --missed query from bin/shoegazegazer.
  # NOTE: Sequel where{} blocks use instance_exec, so instance variables
  # are not visible — capture them as locals before the block.
  def missed_query(run_start:)
    cutoff_30d  = Time.now - (30 * 86_400)
    cutoff_12mo = @cutoff_12mo
    profile     = @profile

    recently_surfaced_ids = @db[:album_scores]
                            .where(profile_name: profile)
                            .where { scored_at >= cutoff_30d }
                            .where { scored_at < run_start }
                            .select(:album_id)

    @db[:albums]
      .join(:album_scores, Sequel[:album_scores][:album_id] => Sequel[:albums][:id])
      .where(Sequel[:album_scores][:profile_name] => profile)
      .where { Sequel[:albums][:release_date] >= cutoff_12mo }
      .where { Sequel[:album_scores][:similarity_score] >= 50 }
      .exclude(Sequel[:albums][:id] => recently_surfaced_ids)
      .order(Sequel.desc(Sequel[:album_scores][:similarity_score]))
      .limit(20)
      .select(
        Sequel[:albums][:id],
        Sequel[:albums][:artist],
        Sequel[:albums][:title],
        Sequel[:albums][:source],
        Sequel[:album_scores][:similarity_score],
        Sequel[:album_scores][:tags].as(:score_tags)
      )
      .all
  end
end

# ---------------------------------------------------------------------------
# Tests for the --stats query logic
# ---------------------------------------------------------------------------
class TestStatsQuery < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
    @profile = 'taste_profile'
  end

  def test_counts_total_albums
    insert_album!(@db, artist: 'A', title: 'X')
    insert_album!(@db, artist: 'B', title: 'Y')

    assert_equal 2, @db[:albums].count
  end

  def test_counts_scored_albums
    a = insert_album!(@db, artist: 'A', title: 'X')
    insert_album!(@db, artist: 'B', title: 'Y')
    insert_score!(@db, album_id: a[:id])

    assert_equal 2, @db[:albums].count
    assert_equal 1, @db[:album_scores].count
  end

  def test_counts_scrape_runs
    Scraper.record_scrape_run(@db, 'aoty', 100)
    Scraper.record_scrape_run(@db, 'musicbrainz', 50)

    assert_equal 2, @db[:scrape_runs].count
  end

  def test_oldest_release_date
    insert_album!(@db, artist: 'New', title: 'A', release_date: Date.today)
    insert_album!(@db, artist: 'Old', title: 'B', release_date: Date.new(2025, 1, 15))

    oldest = @db[:albums].min(:release_date)
    # SQLite min() on a date column returns a string
    assert_equal '2025-01-15', oldest.to_s
  end

  def test_most_recent_scrape
    old_time = Time.now - 86_400
    @db[:scrape_runs].insert(scraped_at: old_time, source: 'aoty', albums_found: 10)
    Scraper.record_scrape_run(@db, 'aoty', 20)

    most_recent = @db[:scrape_runs].max(:scraped_at)
    # SQLite max() on a datetime column may return a string
    parsed = most_recent.is_a?(Time) ? most_recent : Time.parse(most_recent.to_s)
    assert_in_delta Time.now.to_f, parsed.to_f, 5.0
  end

  def test_top_10_ordered_by_similarity_score
    5.times do |i|
      a = insert_album!(@db, artist: "Band #{i}", title: "Album #{i}")
      insert_score!(@db, album_id: a[:id], similarity: 50.0 + (i * 10))
    end

    top = stats_top_10
    assert_equal 5, top.size
    scores = top.map { |r| r[:similarity_score] }
    assert_equal scores.sort.reverse, scores
    assert_in_delta 90.0, scores.first, 0.01
  end

  def test_top_10_filters_by_profile
    a = insert_album!(@db, artist: 'A', title: 'X')
    insert_score!(@db, album_id: a[:id], profile: 'other_profile', similarity: 99.0)

    top = stats_top_10
    assert_empty top
  end

  def test_top_10_limits_to_10
    15.times do |i|
      a = insert_album!(@db, artist: "Band #{i}", title: "Album #{i}")
      insert_score!(@db, album_id: a[:id], similarity: 50.0 + i)
    end

    assert_equal 10, stats_top_10.size
  end

  private

  def stats_top_10
    @db[:album_scores]
      .join(:albums, id: :album_id)
      .where(Sequel[:album_scores][:profile_name] => @profile)
      .order(Sequel.desc(Sequel[:album_scores][:similarity_score]))
      .limit(10)
      .select(Sequel[:albums][:artist],
              Sequel[:albums][:title],
              Sequel[:album_scores][:similarity_score])
      .all
  end
end

# ---------------------------------------------------------------------------
# Tests for score caching logic (used in default weekly run)
# ---------------------------------------------------------------------------
class TestScoreCaching < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
    @profile = 'taste_profile'
  end

  def test_recent_score_is_found_within_12_hours
    album = insert_album!(@db)
    insert_score!(@db, album_id: album[:id], similarity: 70.0,
                       scored_at: Time.now - (6 * 3600)) # 6 hours ago

    twelve_hours_ago = Time.now - (12 * 3600)
    existing = @db[:album_scores]
               .where(album_id: album[:id], profile_name: @profile)
               .where { scored_at >= twelve_hours_ago }
               .first

    refute_nil existing
    assert_in_delta 70.0, existing[:similarity_score], 0.01
  end

  def test_stale_score_not_found_after_12_hours
    album = insert_album!(@db)
    insert_score!(@db, album_id: album[:id], similarity: 70.0,
                       scored_at: Time.now - (13 * 3600)) # 13 hours ago

    twelve_hours_ago = Time.now - (12 * 3600)
    existing = @db[:album_scores]
               .where(album_id: album[:id], profile_name: @profile)
               .where { scored_at >= twelve_hours_ago }
               .first

    assert_nil existing
  end

  def test_cached_score_tags_round_trip_through_json
    album = insert_album!(@db)
    original_tags = ['shoegaze', 'dream pop', 'ambient']
    insert_score!(@db, album_id: album[:id], tags: original_tags)

    row = @db[:album_scores].where(album_id: album[:id]).first
    assert_equal original_tags, JSON.parse(row[:tags])
  end
end

# ---------------------------------------------------------------------------
# Tests for the --missed unscored-detection query
# ---------------------------------------------------------------------------
class TestMissedUnscoredDetection < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
    @profile = 'taste_profile'
  end

  def test_finds_unscored_albums_from_last_12_months
    insert_album!(@db, artist: 'Unscored', title: 'No Score',
                       release_date: Date.today - 60)

    unscored = unscored_query
    assert_equal 1, unscored.size
    assert_equal 'Unscored', unscored.first[:artist]
  end

  def test_excludes_already_scored_albums
    a = insert_album!(@db, artist: 'Scored', title: 'Has Score',
                           release_date: Date.today - 60)
    insert_score!(@db, album_id: a[:id])

    unscored = unscored_query
    assert_empty unscored
  end

  def test_excludes_albums_older_than_12_months
    insert_album!(@db, artist: 'Old', title: 'Ancient',
                       release_date: Date.today - 400)

    unscored = unscored_query
    assert_empty unscored
  end

  def test_album_scored_under_different_profile_still_unscored_for_this_profile
    a = insert_album!(@db, artist: 'Multi', title: 'Profile',
                           release_date: Date.today - 60)
    insert_score!(@db, album_id: a[:id], profile: 'other_profile')

    unscored = unscored_query
    assert_equal 1, unscored.size
  end

  private

  def unscored_query
    cutoff_12mo = Date.today - 365
    @db[:albums]
      .left_join(:album_scores, album_id: :id, profile_name: @profile)
      .where { Sequel[:albums][:release_date] >= cutoff_12mo }
      .where(Sequel[:album_scores][:id] => nil)
      .select_all(:albums)
      .all
  end
end

# ---------------------------------------------------------------------------
# Config name derivation
# ---------------------------------------------------------------------------
class TestConfigName < Minitest::Test
  def test_taste_profile_name_derived_from_filename
    assert_equal 'test_taste_profile', TASTE_PROFILE_NAME
  end

  def test_taste_profile_loads_artists
    assert_includes TASTE_PROFILE[:artists], 'Slowdive'
    assert_includes TASTE_PROFILE[:artists], 'My Bloody Valentine'
  end

  def test_taste_profile_loads_tags
    assert_includes TASTE_PROFILE[:tags], 'shoegaze'
    assert_includes TASTE_PROFILE[:tags], 'dream pop'
  end

  def test_taste_profile_loads_min_score
    assert_equal 60, TASTE_PROFILE[:min_score]
  end
end

# ---------------------------------------------------------------------------
# Apple Music URL generation (still works)
# ---------------------------------------------------------------------------
class TestAppleMusicUrl < Minitest::Test
  def test_encodes_artist_and_title
    url = Scraper.apple_music_url('Slowdive', 'everything is alive')
    assert_includes url, 'music.apple.com/search'
    assert_includes url, 'Slowdive'
    assert_includes url, 'everything'
  end

  def test_encodes_special_characters
    url = Scraper.apple_music_url('Sigur Rós', '( )')
    assert_includes url, 'music.apple.com/search'
    # Should be URL-encoded
    assert_match(/Sigur/, url)
  end
end

# ---------------------------------------------------------------------------
# Number formatting (used in --stats output)
# ---------------------------------------------------------------------------
class TestNumberFormatting < Minitest::Test
  def setup
    @fmt_num = ->(n) { n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse }
  end

  def test_small_number
    assert_equal '42', @fmt_num.call(42)
  end

  def test_thousands
    assert_equal '1,847', @fmt_num.call(1847)
  end

  def test_millions
    assert_equal '1,234,567', @fmt_num.call(1_234_567)
  end

  def test_zero
    assert_equal '0', @fmt_num.call(0)
  end
end
