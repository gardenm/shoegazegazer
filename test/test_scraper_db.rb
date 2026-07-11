# frozen_string_literal: true

require_relative 'test_helper'

class TestScraperNormalise < Minitest::Test
  def test_downcases
    assert_equal 'slowdive', Scraper.normalise('Slowdive')
  end

  def test_strips_punctuation
    assert_equal 'my bloody valentines', Scraper.normalise("My Bloody Valentine's")
  end

  def test_collapses_whitespace
    assert_equal 'beach house', Scraper.normalise('Beach   House')
  end

  def test_strips_leading_trailing_whitespace
    assert_equal 'cocteau twins', Scraper.normalise('  Cocteau Twins  ')
  end

  def test_removes_hyphens_and_parens
    assert_equal 'sunday 1994', Scraper.normalise('Sunday (1994)')
  end

  def test_handles_unicode_punctuation
    # Curly quotes, em dashes
    assert_equal 'its alive', Scraper.normalise('it’s alive')
  end
end

class TestScraperUpsertAlbum < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
  end

  def test_inserts_new_album
    album = make_album(artist: 'Slowdive', title: 'Souvlaki', score: 92)
    Scraper.upsert_album(@db, album)

    row = @db[:albums].first
    assert_equal 'Slowdive', row[:artist]
    assert_equal 'Souvlaki', row[:title]
    assert_equal 92, row[:aoty_score]
    assert_equal 'aoty', row[:source]
    assert_equal 'slowdive', row[:artist_norm]
    assert_equal 'souvlaki', row[:title_norm]
  end

  def test_inserts_album_with_nil_score
    Scraper.upsert_album(@db, make_album(score: nil))
    assert_nil @db[:albums].first[:aoty_score]
  end

  def test_inserts_release_date
    date = Date.new(2026, 3, 15)
    Scraper.upsert_album(@db, make_album(release_date: date))
    assert_equal date, @db[:albums].first[:release_date]
  end

  def test_conflict_updates_score_when_new_is_non_nil
    Scraper.upsert_album(@db, make_album(score: 80))
    Scraper.upsert_album(@db, make_album(score: 92))

    assert_equal 1, @db[:albums].count
    assert_equal 92, @db[:albums].first[:aoty_score]
  end

  def test_conflict_preserves_score_when_new_is_nil
    Scraper.upsert_album(@db, make_album(score: 85))
    Scraper.upsert_album(@db, make_album(score: nil))

    assert_equal 85, @db[:albums].first[:aoty_score]
  end

  def test_conflict_updates_url_when_new_is_non_nil
    Scraper.upsert_album(@db, make_album(url: 'https://old.com'))
    Scraper.upsert_album(@db, make_album(url: 'https://new.com'))

    assert_equal 'https://new.com', @db[:albums].first[:url]
  end

  def test_conflict_preserves_url_when_new_is_nil
    Scraper.upsert_album(@db, make_album(url: 'https://old.com'))
    Scraper.upsert_album(@db, make_album(url: nil))

    assert_equal 'https://old.com', @db[:albums].first[:url]
  end

  def test_dedup_is_case_insensitive
    Scraper.upsert_album(@db, make_album(artist: 'Slowdive', title: 'Souvlaki'))
    Scraper.upsert_album(@db, make_album(artist: 'SLOWDIVE', title: 'SOUVLAKI'))

    assert_equal 1, @db[:albums].count
  end

  def test_dedup_ignores_punctuation_differences
    Scraper.upsert_album(@db, make_album(artist: 'Slowdive', title: 'Souvlaki'))
    Scraper.upsert_album(@db, make_album(artist: 'Slowdive', title: 'Souvlaki!'))

    assert_equal 1, @db[:albums].count
  end

  def test_different_albums_get_separate_rows
    Scraper.upsert_album(@db, make_album(artist: 'Slowdive', title: 'Souvlaki'))
    Scraper.upsert_album(@db, make_album(artist: 'Slowdive', title: 'Pygmalion'))

    assert_equal 2, @db[:albums].count
  end

  def test_sets_created_at
    Scraper.upsert_album(@db, make_album)
    refute_nil @db[:albums].first[:created_at]
  end
end

class TestScraperScrapeRuns < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
  end

  def test_record_scrape_run_inserts_row
    Scraper.record_scrape_run(@db, 'aoty', 150)

    row = @db[:scrape_runs].first
    assert_equal 'aoty', row[:source]
    assert_equal 150, row[:albums_found]
    refute_nil row[:scraped_at]
  end

  def test_record_scrape_run_allows_multiple_per_source
    Scraper.record_scrape_run(@db, 'aoty', 100)
    Scraper.record_scrape_run(@db, 'aoty', 105)

    assert_equal 2, @db[:scrape_runs].where(source: 'aoty').count
  end

  def test_todays_scrape_true_when_run_exists_today
    Scraper.record_scrape_run(@db, 'aoty', 50)
    assert Scraper.todays_scrape?(@db)
  end

  def test_todays_scrape_false_when_no_runs
    refute Scraper.todays_scrape?(@db)
  end

  def test_todays_scrape_false_when_only_yesterday
    yesterday = Time.now - (24 * 60 * 60)
    @db[:scrape_runs].insert(scraped_at: yesterday, source: 'aoty', albums_found: 50)

    refute Scraper.todays_scrape?(@db)
  end
end

class TestScraperRecentAlbums < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
  end

  def test_returns_albums_within_date_range
    insert_album!(@db, artist: 'Slowdive', title: 'A', release_date: Date.today)
    insert_album!(@db, artist: 'MBV', title: 'B', release_date: Date.today - 7)

    albums = Scraper.recent_albums(@db, days: 14)
    assert_equal 2, albums.size
  end

  def test_excludes_albums_older_than_range
    insert_album!(@db, artist: 'Slowdive', title: 'New', release_date: Date.today)
    insert_album!(@db, artist: 'MBV', title: 'Old', release_date: Date.today - 30)

    albums = Scraper.recent_albums(@db, days: 14)
    assert_equal 1, albums.size
    assert_equal 'Slowdive', albums.first[:artist]
  end

  def test_maps_columns_to_expected_keys
    insert_album!(@db, artist: 'Slowdive', title: 'Souvlaki', score: 88,
                       source: 'aoty', url: 'https://example.com',
                       release_date: Date.today)

    album = Scraper.recent_albums(@db).first
    assert_equal 'Slowdive', album[:artist]
    assert_equal 'Souvlaki', album[:title]
    assert_equal 88, album[:score]           # mapped from aoty_score
    assert_equal 'aoty', album[:source]
    assert_equal 'https://example.com', album[:url]
    refute_nil album[:id]
    refute_nil album[:release_date]
  end

  def test_returns_empty_array_when_no_recent_albums
    assert_equal [], Scraper.recent_albums(@db)
  end

  def test_custom_days_parameter
    insert_album!(@db, artist: 'Slowdive', title: 'A', release_date: Date.today - 5)

    assert_equal 1, Scraper.recent_albums(@db, days: 7).size
    assert_equal 0, Scraper.recent_albums(@db, days: 3).size
  end
end
