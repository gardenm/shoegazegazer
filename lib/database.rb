# frozen_string_literal: true

require 'sequel'
require 'fileutils'

# SQLite persistence layer. Albums are stored once (deduplicated on a
# normalised artist/title pair) and scored per taste profile, so multiple
# profiles can coexist against the same album catalogue.
module Database
  DB_PATH = ENV.fetch('SHOEGAZEGAZER_DB',
                      File.expand_path('../db/shoegazegazer.db', __dir__))

  def self.db
    @db ||= begin
      FileUtils.mkdir_p(File.dirname(DB_PATH))
      Sequel.sqlite(DB_PATH)
    end
  end

  # Idempotent: safe to call on every startup.
  def self.migrate
    connection = db

    connection.create_table?(:albums) do
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

    connection.create_table?(:scrape_runs) do
      primary_key :id
      DateTime :scraped_at, null: false
      String :source, null: false
      Integer :albums_found
    end

    connection.create_table?(:ratings) do
      primary_key :id
      foreign_key :album_id, :albums, null: false
      String :profile_name, null: false
      Integer :rating, null: false # +1 (more like this) or -1 (less)
      DateTime :rated_at
      unique %i[album_id profile_name]
    end

    connection.create_table?(:album_scores) do
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

    connection
  end
end
