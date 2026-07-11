# frozen_string_literal: true

require 'minitest/autorun'
require 'sequel'
require 'json'
require 'date'

# Point config at the test fixture before any app code loads
ENV['SHOEGAZEGAZER_CONFIG'] = File.expand_path('fixtures/test_taste_profile.yml', __dir__)

require_relative '../lib/config'
require_relative '../lib/database'
require_relative '../lib/scraper'
require_relative '../lib/lastfm'
require_relative '../lib/scorer'
require_relative '../lib/feedback'

# Shared helpers for tests that need an in-memory SQLite database.
# Each test gets a fresh DB — no cross-test pollution.
module TestDBHelper
  def create_test_db
    db = Sequel.sqlite # in-memory
    apply_schema(db)
    db
  end

  private

  def apply_schema(db)
    db.create_table(:albums) do
      primary_key :id
      String :artist, null: false
      String :title, null: false
      Date :release_date
      String :source
      String :url, text: true
      Integer :aoty_score
      String :artist_norm, null: false
      String :title_norm, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      unique %i[artist_norm title_norm]
    end

    db.create_table(:scrape_runs) do
      primary_key :id
      DateTime :scraped_at, null: false
      String :source, null: false
      Integer :albums_found
    end

    db.create_table(:ratings) do
      primary_key :id
      foreign_key :album_id, :albums, null: false
      String :profile_name, null: false
      Integer :rating, null: false
      DateTime :rated_at
      unique %i[album_id profile_name]
    end

    db.create_table(:album_scores) do
      primary_key :id
      foreign_key :album_id, :albums
      String :profile_name, null: false
      Float :similarity_score
      Float :artist_score
      Float :tag_score
      Float :metacritic_score
      String :tags, text: true
      DateTime :scored_at
      unique %i[album_id profile_name]
    end
  end

  # Convenience: build an album hash the way Scraper returns one
  def make_album(overrides = {})
    {
      artist: 'Slowdive',
      title: 'everything is alive',
      release_date: Date.today,
      source: 'aoty',
      url: 'https://www.albumoftheyear.org/album/1234',
      score: 85
    }.merge(overrides)
  end

  # Insert an album via Scraper.upsert_album and return the DB row
  def insert_album!(db, overrides = {})
    Scraper.upsert_album(db, make_album(overrides))
    norm_artist = Scraper.normalise(overrides.fetch(:artist, 'Slowdive'))
    norm_title  = Scraper.normalise(overrides.fetch(:title, 'everything is alive'))
    db[:albums].where(artist_norm: norm_artist, title_norm: norm_title).first
  end

  # Insert a score directly and return the DB row
  def insert_score!(db, album_id:, profile: 'taste_profile', similarity: 75.0,
                    artist: 20.0, tag: 30.0, meta: 25.0,
                    tags: ['shoegaze'], scored_at: Time.now)
    Scorer.upsert_score(
      db,
      album_id: album_id,
      profile_name: profile,
      breakdown: { total: similarity, artist_score: artist, tag_score: tag, metacritic_score: meta },
      tags: tags
    )
    # Patch scored_at if caller wants a specific time (upsert_score uses Time.now)
    unless scored_at.nil?
      db[:album_scores]
        .where(album_id: album_id, profile_name: profile)
        .update(scored_at: scored_at)
    end
    db[:album_scores].where(album_id: album_id, profile_name: profile).first
  end
end
