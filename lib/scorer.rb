# frozen_string_literal: true

require 'json'
require 'sequel'
require_relative 'config'
require_relative 'lastfm'

module Scorer
  PROFILE_ARTISTS_DOWNCASED = TASTE_PROFILE[:artists].map(&:downcase).freeze

  def self.score(album)
    artist_score(album[:artist]) +
      tag_score(album[:artist], album[:tags]) +
      metacritic_score(album[:metacritic_score])
  end

  def self.score_breakdown(album)
    a = artist_score(album[:artist])
    t = tag_score(album[:artist], album[:tags])
    m = metacritic_score(album[:metacritic_score])
    { artist_score: a, tag_score: t, metacritic_score: m, total: a + t + m }
  end

  def self.artist_score(artist)
    return 40.0 if PROFILE_ARTISTS_DOWNCASED.include?(artist.downcase)

    best_match = LastFm.similar_artists(artist)
                       .select { |s| PROFILE_ARTISTS_DOWNCASED.include?(s[:name].downcase) }
                       .map { |s| s[:match] }
                       .max

    best_match ? best_match * 35.0 : 0.0
  end

  def self.tag_score(artist, album_tags)
    all_tags = (Array(album_tags) + LastFm.artist_tags(artist)).map(&:downcase).uniq
    overlap  = (all_tags & TASTE_PROFILE[:tags]).size
    [overlap, 5].min / 5.0 * 35.0
  end

  def self.metacritic_score(score)
    return 12.0 if score.nil?

    (score / 100.0) * 25.0
  end

  # Persist a score breakdown for one album under one profile.
  # Re-scoring the same album+profile overwrites the previous row.
  def self.upsert_score(db, album_id:, profile_name:, breakdown:, tags:)
    db[:album_scores].insert_conflict(
      target: %i[album_id profile_name],
      update: {
        similarity_score: Sequel[:excluded][:similarity_score],
        artist_score: Sequel[:excluded][:artist_score],
        tag_score: Sequel[:excluded][:tag_score],
        metacritic_score: Sequel[:excluded][:metacritic_score],
        tags: Sequel[:excluded][:tags],
        scored_at: Sequel[:excluded][:scored_at]
      }
    ).insert(
      album_id: album_id,
      profile_name: profile_name,
      similarity_score: breakdown[:total],
      artist_score: breakdown[:artist_score],
      tag_score: breakdown[:tag_score],
      metacritic_score: breakdown[:metacritic_score],
      tags: JSON.generate(tags),
      scored_at: Time.now
    )
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'dotenv/load'

  test_cases = [
    { artist: 'Slowdive',      title: 'Test Album', tags: ['shoegaze', 'dream pop'], metacritic_score: 85 },
    { artist: 'Taylor Swift',  title: 'Test Album', tags: ['pop'],                   metacritic_score: 90 },
    { artist: 'Fleeting Joys', title: 'Test Album', tags: ['shoegaze'],              metacritic_score: nil }
  ]

  test_cases.each do |album|
    result = Scorer.score(album)
    puts format('%-20s => %.2f / 100', album[:artist], result)
  end
end
