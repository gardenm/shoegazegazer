require_relative "config"
require_relative "lastfm"

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

  private

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
end

if __FILE__ == $0
  require "dotenv/load"

  test_cases = [
    { artist: "Slowdive",      title: "Test Album", tags: ["shoegaze", "dream pop"], metacritic_score: 85 },
    { artist: "Taylor Swift",  title: "Test Album", tags: ["pop"],                   metacritic_score: 90 },
    { artist: "Fleeting Joys", title: "Test Album", tags: ["shoegaze"],              metacritic_score: nil },
  ]

  test_cases.each do |album|
    result = Scorer.score(album)
    puts "%-20s => %.2f / 100" % [album[:artist], result]
  end
end
