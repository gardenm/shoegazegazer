# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require_relative '../web/app'

class TestWebApp < Minitest::Test
  include Rack::Test::Methods
  include TestDBHelper

  def app
    ShoegazegazerWeb
  end

  def setup
    # Point the app's Database module at a fresh in-memory DB
    @db = create_test_db
    Database.instance_variable_set(:@db, @db)
  end

  def teardown
    Database.instance_variable_set(:@db, nil)
  end

  def seed_scored_album!(artist: 'Slowdive', title: 'everything is alive',
                         profile: 'shoegaze', similarity: 82.0,
                         release_date: Date.today - 3)
    album = insert_album!(@db, artist: artist, title: title, release_date: release_date)
    insert_score!(@db, album_id: album[:id], profile: profile, similarity: similarity)
    album
  end

  # --- / ---

  def test_root_redirects_to_first_profile
    seed_scored_album!(profile: 'ambient')
    get '/'

    assert_equal 302, last_response.status
    assert_includes last_response.headers['Location'], '/p/ambient'
  end

  def test_root_with_empty_db_shows_empty_state
    # No scores in DB, but profile ymls exist on disk → redirects to first
    get '/'
    assert_includes [200, 302], last_response.status
  end

  # --- /p/:profile ---

  def test_profile_page_lists_recent_album
    seed_scored_album!(artist: 'Whirr', title: 'Feels Like You', profile: 'shoegaze')
    get '/p/shoegaze'

    assert last_response.ok?
    assert_includes last_response.body, 'Whirr'
    assert_includes last_response.body, 'Feels Like You'
  end

  def test_profile_page_escapes_html_in_album_data
    seed_scored_album!(artist: '<script>alert(1)</script>', title: 'XSS')
    get '/p/shoegaze'

    assert last_response.ok?
    refute_includes last_response.body, '<script>alert(1)</script>'
    assert_includes last_response.body, '&lt;script&gt;'
  end

  def test_profile_page_shows_back_catalogue_high_scorers
    seed_scored_album!(artist: 'Hotline TNT', title: 'Raspberry Moon',
                       similarity: 75.0, release_date: Date.today - 100)
    get '/p/shoegaze'

    assert last_response.ok?
    assert_includes last_response.body, 'Hotline TNT'
  end

  def test_back_catalogue_excludes_low_scorers
    seed_scored_album!(artist: 'Low Scorer', title: 'Meh',
                       similarity: 30.0, release_date: Date.today - 100)
    get '/p/shoegaze'

    assert last_response.ok?
    refute_includes last_response.body, 'Low Scorer'
  end

  def test_unknown_profile_404s
    get '/p/does_not_exist'
    assert_equal 404, last_response.status
  end

  def test_profiles_scored_in_db_appear_in_nav
    seed_scored_album!(profile: 'krautrock')
    get '/p/krautrock'

    assert last_response.ok?
    assert_includes last_response.body, 'krautrock'
  end

  # --- /stats ---

  def test_stats_page_renders
    seed_scored_album!
    Scraper.record_scrape_run(@db, 'aoty', 42)
    get '/stats'

    assert last_response.ok?
    assert_includes last_response.body, 'albums tracked'
    assert_includes last_response.body, 'shoegaze'
  end

  # --- /api/digest/:profile ---

  def test_api_digest_returns_json
    seed_scored_album!(artist: 'Panchiko', title: 'Ginkgo', similarity: 72.5)
    get '/api/digest/shoegaze'

    assert last_response.ok?
    assert_includes last_response.content_type, 'application/json'

    digest = JSON.parse(last_response.body)
    assert_equal 1, digest.size
    assert_equal 'Panchiko', digest.first['artist']
    assert_in_delta 72.5, digest.first['similarity_score'], 0.01
    assert_includes digest.first['apple_music_url'], 'music.apple.com'
  end

  def test_api_digest_unknown_profile_404s
    get '/api/digest/nope'
    assert_equal 404, last_response.status
  end

  def test_api_digest_excludes_old_releases
    seed_scored_album!(artist: 'Old Band', title: 'Ancient',
                       release_date: Date.today - 60)
    get '/api/digest/shoegaze'

    digest = JSON.parse(last_response.body)
    assert_empty digest
  end
end
