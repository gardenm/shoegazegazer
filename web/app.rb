# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'date'
require 'uri'
require_relative '../lib/database'
require_relative '../lib/feedback'

# Read-only browser for the score database. Scraping and scoring stay in
# the CLI — this just makes the results pleasant to explore, so it runs
# without a Last.fm API key.
class ShoegazegazerWeb < Sinatra::Base
  PROFILES_DIR = File.expand_path('../config/profiles', __dir__)

  set :views, File.expand_path('views', __dir__)
  set :public_folder, File.expand_path('public', __dir__)
  # Personal tool served on localhost — skip Host-header authorization
  set :host_authorization, { permitted_hosts: [] }

  helpers do
    def db
      Database.db
    end

    # Profiles seen in the database plus any yml waiting in config/profiles
    def profiles
      scored = db[:album_scores].distinct.select_map(:profile_name)
      on_disk = Dir[File.join(PROFILES_DIR, '*.yml')].map { |p| File.basename(p, '.yml') }
      (scored + on_disk).uniq.sort
    end

    def scored_albums(profile)
      db[:albums]
        .join(:album_scores, album_id: :id)
        .left_join(:ratings, album_id: Sequel[:albums][:id],
                             profile_name: profile)
        .where(Sequel[:album_scores][:profile_name] => profile)
        .select(
          Sequel[:albums][:id].as(:album_id),
          Sequel[:albums][:artist],
          Sequel[:albums][:title],
          Sequel[:albums][:release_date],
          Sequel[:albums][:source],
          Sequel[:albums][:url],
          Sequel[:albums][:aoty_score],
          Sequel[:album_scores][:similarity_score],
          Sequel[:album_scores][:tags],
          Sequel[:ratings][:rating]
        )
    end

    def recent_digest(profile, days: 14, limit: 50)
      cutoff = Date.today - days
      scored_albums(profile)
        .where { Sequel[:albums][:release_date] >= cutoff }
        .order(Sequel.desc(Sequel[:album_scores][:similarity_score]))
        .limit(limit)
        .all
    end

    def back_catalogue(profile, months: 12, min_similarity: 50, limit: 50)
      cutoff = Date.today - (months * 30)
      scored_albums(profile)
        .where { Sequel[:albums][:release_date] >= cutoff }
        .where { Sequel[:album_scores][:similarity_score] >= min_similarity }
        .order(Sequel.desc(Sequel[:album_scores][:similarity_score]))
        .limit(limit)
        .all
    end

    def parse_tags(json)
      JSON.parse(json || '[]').first(4)
    rescue JSON::ParserError
      []
    end

    def apple_music_url(artist, title)
      term = URI.encode_www_form_component("#{artist} #{title}")
      "https://music.apple.com/search?term=#{term}"
    end

    def score_class(score)
      if score >= 70 then 'score-high'
      elsif score >= 50 then 'score-mid'
      else 'score-low'
      end
    end

    def h(text)
      Rack::Utils.escape_html(text.to_s)
    end
  end

  # Web app manifest so Safari's "Add to Dock" (and any browser's
  # "install app") gives shoegazegazer its own icon and window.
  get '/manifest.webmanifest' do
    content_type 'application/manifest+json'
    {
      name: 'shoegazegazer',
      short_name: 'shoegazegazer',
      description: 'New releases, scored against your taste profiles',
      start_url: '/',
      display: 'standalone',
      background_color: '#14121a',
      theme_color: '#14121a',
      icons: [{ src: '/icon-512.png', sizes: '512x512', type: 'image/png' }]
    }.to_json
  end

  get '/' do
    first = profiles.first
    halt 200, erb(:empty) if first.nil?

    redirect to("/p/#{first}")
  end

  get '/p/:profile' do
    @profile = params[:profile]
    halt 404, "Unknown profile: #{h(@profile)}" unless profiles.include?(@profile)

    @recent = recent_digest(@profile)
    @catalogue = back_catalogue(@profile)
    erb :profile
  end

  # Thumbs up/down. Stores the rating, then instantly re-ranks the whole
  # profile from the saved score components — no Last.fm calls.
  post '/rate' do
    profile = params[:profile]
    halt 404, "Unknown profile: #{h(profile)}" unless profiles.include?(profile)

    rating = begin
      Integer(params[:rating])
    rescue StandardError
      nil
    end
    album_id = begin
      Integer(params[:album_id])
    rescue StandardError
      nil
    end
    halt 400, 'rating must be -1, 0, or 1' unless [-1, 0, 1].include?(rating)
    halt 400, 'unknown album' if album_id.nil? || db[:albums].where(id: album_id).empty?

    Feedback.upsert_rating(db, album_id: album_id, profile_name: profile, rating: rating)
    Feedback.reapply(db, profile)
    redirect to("/p/#{profile}")
  end

  get '/stats' do
    @total_albums = db[:albums].count
    @scrape_runs  = db[:scrape_runs].count
    @last_scrape  = db[:scrape_runs].max(:scraped_at)
    @oldest       = db[:albums].min(:release_date)
    @per_profile  = db[:album_scores]
                    .group_and_count(:profile_name)
                    .order(:profile_name)
                    .all
    erb :stats
  end

  # Machine-readable digest, e.g. for a phone shortcut or RSS bridge
  get '/api/digest/:profile' do
    profile = params[:profile]
    halt 404, { error: 'unknown profile' }.to_json unless profiles.include?(profile)

    content_type :json
    recent_digest(profile).map do |row|
      {
        artist: row[:artist],
        title: row[:title],
        release_date: row[:release_date].to_s,
        similarity_score: row[:similarity_score],
        tags: parse_tags(row[:tags]),
        source: row[:source],
        url: row[:url],
        apple_music_url: apple_music_url(row[:artist], row[:title])
      }
    end.to_json
  end
end
