# frozen_string_literal: true

require 'tty-table'
require 'pastel'
require_relative 'lastfm'

module Formatter
  PASTEL = Pastel.new

  ARTIST_WIDTH = 25
  TITLE_WIDTH  = 45

  def self.print_results(albums)
    rows = albums.each_with_index.map do |album, i|
      [
        i + 1,
        truncate(album[:artist], ARTIST_WIDTH),
        truncate(album[:title],  TITLE_WIDTH),
        score_cell(album[:similarity_score]),
        source_cell(album[:source]),
        tags_cell(album),
        "→ #{i + 1}"
      ]
    end

    table = TTY::Table.new(
      header: ['RANK', 'ARTIST', 'TITLE', 'SCORE', 'SOURCE', 'TAGS', 'APPLE MUSIC'],
      rows: rows
    )

    # Total: borders(8) + padding(14) + content(4+25+45+5+6+28+10=123) = 145
    puts table.render(:unicode,
                      padding: [0, 1],
                      column_widths: [4, ARTIST_WIDTH, TITLE_WIDTH, 5, 6, 28, 10],
                      width: 160,
                      multiline: false) do |renderer|
      renderer.border.separator = :each_row
    end

    puts
    puts PASTEL.dim('Apple Music links:')
    albums.each_with_index do |album, i|
      puts "  #{i + 1}. #{album[:apple_music_url]}"
    end
  end

  def self.truncate(str, max)
    return str if str.length <= max

    "#{str[0, max - 1]}…"
  end

  def self.score_cell(score)
    text = score.round(1).to_s
    if score >= 70
      PASTEL.green(text)
    elsif score >= 50
      PASTEL.yellow(text)
    else
      PASTEL.red(text)
    end
  end

  def self.tags_cell(album)
    tags = Array(album[:tags])
    tags = LastFm.artist_tags(album[:artist]) if tags.empty?
    tags.first(3).join(', ')
  end

  def self.source_cell(source)
    case source
    when 'aoty'         then PASTEL.cyan('aoty')
    when 'metacritic'   then PASTEL.yellow('metacritic')
    when 'musicbrainz'  then PASTEL.magenta('musicbrainz')
    else source
    end
  end
end
