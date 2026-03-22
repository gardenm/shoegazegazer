# frozen_string_literal: true

require 'httparty'
require 'nokogiri'
require 'uri'
require 'date'
require 'json'

module Scraper
  BASE_URL     = 'https://www.albumoftheyear.org'
  RELEASES_URL = "#{BASE_URL}/releases/".freeze
  HEADERS = {
    'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept-Language' => 'en-US,en;q=0.9'
  }.freeze

  def self.fetch_aoty(pages: 4, days_recent: 14)
    today    = Date.today
    cutoff   = today - days_recent
    seen     = {}
    albums   = []

    pages.times do |i|
      page_num = i + 1
      url = page_num == 1 ? RELEASES_URL : "#{RELEASES_URL}?p=#{page_num}"

      resp = HTTParty.get(url, headers: HEADERS)
      doc  = Nokogiri::HTML(resp.body)

      doc.css('.albumBlock').each do |block|
        artist = block.at_css('.artistTitle')&.text&.strip
        title  = block.at_css('.albumTitle')&.text&.strip
        next if artist.nil? || title.nil?

        key = "#{artist} #{title}".downcase
        next if seen.key?(key)

        seen[key] = true

        release_date = parse_date(block.at_css('.type')&.text&.strip, today)
        next if release_date.nil? || release_date < cutoff

        href  = block.at_css('.image a')&.[]('href')
        url_  = href ? "#{BASE_URL}#{href}" : nil

        raw_score = block.at_css('.rating')&.text&.strip
        score = raw_score && !raw_score.empty? ? raw_score.to_i : nil

        albums << {
          artist: artist,
          title: title,
          score: score,
          source: 'aoty',
          url: url_,
          release_date: release_date
        }
      end

      sleep 1 if i < pages - 1
    end

    albums
  end

  def self.dedup(albums)
    groups = albums.group_by { |a| normalise("#{a[:artist]} #{a[:title]}") }
    groups.values.map do |dupes|
      dupes.find { |a| !a[:score].nil? } || dupes.first
    end
  end

  MB_API     = 'https://musicbrainz.org/ws/2/release-group'
  MB_HEADERS = { 'User-Agent' => 'shoegazegazer/1.0 (personal music discovery tool)' }.freeze

  def self.fetch_musicbrainz(days_recent: 14, pages: 2)
    today  = Date.today
    cutoff = today - days_recent
    from   = cutoff.strftime('%Y-%m-%d')
    to     = today.strftime('%Y-%m-%d')
    query  = "firstreleasedate:[#{from} TO #{to}] AND primarytype:Album"

    albums = []
    seen   = {}

    pages.times do |i|
      resp = HTTParty.get(MB_API, headers: MB_HEADERS, query: {
                            type: 'album',
                            fmt: 'json',
                            limit: 100,
                            offset: i * 100,
                            query: query
                          })

      groups = JSON.parse(resp.body)['release-groups'] || []

      groups.each do |item|
        artist = mb_artist_credit(item['artist-credit'])
        title  = item['title']
        next if artist.nil? || title.nil?

        key = normalise("#{artist} #{title}")
        next if seen.key?(key)

        seen[key] = true

        release_date = parse_mb_date(item['first-release-date'])
        next if release_date.nil? || release_date < cutoff

        albums << {
          artist: artist,
          title: title,
          score: nil,
          source: 'musicbrainz',
          url: nil,
          release_date: release_date
        }
      end

      sleep 1 if i < pages - 1
    end

    albums
  end

  def self.apple_music_url(artist, title)
    term = URI.encode_www_form_component("#{artist} #{title}")
    "https://music.apple.com/search?term=#{term}"
  end

  def self.mb_artist_credit(credits)
    return nil if credits.nil? || credits.empty?

    credits.filter_map { |c| c.is_a?(Hash) ? c['name'] : nil }.join(', ')
  end

  # Parses "2026-03-08", "2026-03", or "2026" → Date, defaulting to 1st of month/year.
  def self.parse_mb_date(str)
    return nil if str.nil? || str.empty?

    case str
    when /^\d{4}-\d{2}-\d{2}$/ then Date.parse(str)
    when /^\d{4}-\d{2}$/        then Date.new(str[0, 4].to_i, str[5, 2].to_i, 1)
    when /^\d{4}$/              then Date.new(str.to_i, 1, 1)
    end
  rescue ArgumentError
    nil
  end

  def self.normalise(str)
    str.downcase.gsub(/[[:punct:]]/, '').gsub(/\s+/, ' ').strip
  end

  # Parses "Mar 21 • LP" → Date. Year is inferred: if the month/day would be
  # in the future relative to today, it belongs to the previous year.
  def self.parse_date(type_text, today = Date.today)
    return nil if type_text.nil?

    date_part = type_text.split('•').first.strip # "Mar 21"
    return nil if date_part.empty?

    parsed = begin
      Date.strptime(date_part, '%b %d')
    rescue StandardError
      nil
    end
    return nil if parsed.nil?

    candidate = Date.new(today.year, parsed.month, parsed.day)
    candidate > today ? Date.new(today.year - 1, parsed.month, parsed.day) : candidate
  end
end

if __FILE__ == $PROGRAM_NAME
  puts 'Fetching MusicBrainz new releases (2 pages)...'
  albums = Scraper.fetch_musicbrainz(days_recent: 14, pages: 2)

  puts "Found #{albums.size} albums in the last 14 days\n\n"
  puts format('%-32s %-42s %s', 'ARTIST', 'TITLE', 'RELEASE DATE')
  puts '-' * 90
  albums.first(10).each do |a|
    puts format('%-32s %-42s %s', a[:artist].to_s[0, 31], a[:title].to_s[0, 41], a[:release_date].to_s)
  end
end
