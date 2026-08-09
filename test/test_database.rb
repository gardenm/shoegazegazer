# frozen_string_literal: true

require_relative 'test_helper'

class TestDatabaseSchema < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
  end

  # --- Table existence ---

  def test_creates_albums_table
    assert_includes @db.tables, :albums
  end

  def test_creates_scrape_runs_table
    assert_includes @db.tables, :scrape_runs
  end

  def test_creates_album_scores_table
    assert_includes @db.tables, :album_scores
  end

  # --- Albums columns ---

  def test_albums_has_expected_columns
    cols = @db.schema(:albums).map(&:first)
    expected = %i[id artist title release_date source url aoty_score
                  artist_norm title_norm created_at]
    expected.each { |col| assert_includes cols, col, "albums missing column #{col}" }
  end

  def test_albums_artist_not_null
    info = @db.schema(:albums).to_h
    assert_equal false, info[:artist][:allow_null]
  end

  def test_albums_title_not_null
    info = @db.schema(:albums).to_h
    assert_equal false, info[:title][:allow_null]
  end

  def test_albums_aoty_score_nullable
    info = @db.schema(:albums).to_h
    assert_equal true, info[:aoty_score][:allow_null]
  end

  # --- Scrape runs columns ---

  def test_scrape_runs_has_expected_columns
    cols = @db.schema(:scrape_runs).map(&:first)
    %i[id scraped_at source albums_found].each do |col|
      assert_includes cols, col
    end
  end

  def test_scrape_runs_scraped_at_not_null
    info = @db.schema(:scrape_runs).to_h
    assert_equal false, info[:scraped_at][:allow_null]
  end

  # --- Album scores columns ---

  def test_album_scores_has_expected_columns
    cols = @db.schema(:album_scores).map(&:first)
    expected = %i[id album_id profile_name similarity_score artist_score
                  tag_score metacritic_score tags scored_at]
    expected.each { |col| assert_includes cols, col, "album_scores missing column #{col}" }
  end

  def test_album_scores_profile_name_not_null
    info = @db.schema(:album_scores).to_h
    assert_equal false, info[:profile_name][:allow_null]
  end

  # --- Unique constraints ---

  def test_albums_unique_constraint_on_normalised_artist_title
    @db[:albums].insert(artist: 'Slowdive', title: 'Souvlaki', artist_norm: 'slowdive',
                        title_norm: 'souvlaki', created_at: Time.now)
    assert_raises(Sequel::UniqueConstraintViolation) do
      @db[:albums].insert(artist: 'SLOWDIVE', title: 'SOUVLAKI', artist_norm: 'slowdive',
                          title_norm: 'souvlaki', created_at: Time.now)
    end
  end

  def test_album_scores_unique_constraint_on_album_id_and_profile
    row = insert_album!(@db)
    @db[:album_scores].insert(album_id: row[:id], profile_name: 'taste_profile',
                              similarity_score: 50.0, scored_at: Time.now)
    assert_raises(Sequel::UniqueConstraintViolation) do
      @db[:album_scores].insert(album_id: row[:id], profile_name: 'taste_profile',
                                similarity_score: 60.0, scored_at: Time.now)
    end
  end

  def test_album_scores_allows_different_profiles_for_same_album
    row = insert_album!(@db)
    @db[:album_scores].insert(album_id: row[:id], profile_name: 'profile_a',
                              similarity_score: 50.0, scored_at: Time.now)
    @db[:album_scores].insert(album_id: row[:id], profile_name: 'profile_b',
                              similarity_score: 60.0, scored_at: Time.now)
    assert_equal 2, @db[:album_scores].where(album_id: row[:id]).count
  end

  # --- Idempotent migrations ---

  def test_database_migrate_is_idempotent
    # Use a temp file DB so we can test the real Database module
    db_path = File.join(Dir.tmpdir, "shoegazegazer_test_#{$$}.db")
    begin
      # Monkey-patch the constant for this test
      old_path = Database::DB_PATH
      Database.send(:remove_const, :DB_PATH)
      Database.const_set(:DB_PATH, db_path)
      Database.instance_variable_set(:@db, nil)

      Database.migrate
      Database.migrate # second call should not raise

      db = Database.db
      assert_equal 4, db.tables.size
    ensure
      Database.send(:remove_const, :DB_PATH)
      Database.const_set(:DB_PATH, old_path)
      Database.instance_variable_set(:@db, nil)
      FileUtils.rm_f(db_path)
    end
  end
end
