require "httparty"

module LastFm
  BASE_URI = "https://ws.audioscrobbler.com/2.0/".freeze

  @cache = {}

  TAG_BLOCKLIST = [
    "seen live", "favourite albums", "aoty", "albums i own",
    "favorites", "beautiful", "amazing", "good", "great", "love"
  ].freeze

  def self.clean_tags(tags)
    tags.reject { |t| t.length < 3 || t.match?(/^\d{4}$/) || TAG_BLOCKLIST.include?(t) }
  end

  def self.artist_tags(artist)
    fetch(:artist_tags, artist) do
      resp = get(method: "artist.getTopTags", artist: artist)
      return [] if resp.key?("error")

      tags = resp.dig("toptags", "tag") || []
      clean_tags(tags.map { |t| t["name"].downcase }).first(10)
    end
  end

  def self.similar_artists(artist)
    fetch(:similar_artists, artist) do
      resp = get(method: "artist.getSimilar", artist: artist, limit: 15)
      return [] if resp.key?("error")

      artists = resp.dig("similarartists", "artist") || []
      artists.first(15).map { |a| { name: a["name"], match: a["match"].to_f } }
    end
  end

  def self.album_tags(artist, album)
    fetch(:album_tags, "#{artist}|#{album}") do
      resp = get(method: "album.getTopTags", artist: artist, album: album)
      return [] if resp.key?("error")

      tags = resp.dig("toptags", "tag") || []
      clean_tags(tags.map { |t| t["name"].downcase }).first(10)
    end
  end

  private

  def self.get(params)
    HTTParty.get(BASE_URI, query: params.merge(
      api_key: ENV.fetch("LASTFM_API_KEY"),
      format: "json"
    )).parsed_response
  end

  def self.fetch(type, key)
    cache_key = [type, key]
    return @cache[cache_key] if @cache.key?(cache_key)

    @cache[cache_key] = yield
  end
end

if __FILE__ == $0
  require "dotenv/load"
  require "pp"

  artist = "Slowdive"
  puts "=== artist_tags(#{artist}) ==="
  pp LastFm.artist_tags(artist)

  puts "\n=== similar_artists(#{artist}) ==="
  pp LastFm.similar_artists(artist)

  puts "\n=== album_tags(#{artist}, 'Souvlaki') ==="
  pp LastFm.album_tags(artist, "Souvlaki")
end
