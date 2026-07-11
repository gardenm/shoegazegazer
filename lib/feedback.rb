# frozen_string_literal: true

require 'json'
require 'sequel'

# The feedback loop: thumbs up/down ratings adjust future scores for the
# same profile. Artists you liked get a boost, artists you disliked get
# sunk, and the tags of rated albums build a per-profile tag affinity.
#
# Deliberately independent of the taste-profile config and Last.fm — it
# works purely from the database, so the web UI can use it too.
module Feedback
  ARTIST_LIKE_BOOST      = 12.0
  ARTIST_DISLIKE_PENALTY = 15.0
  TAG_AFFINITY_STEP      = 1.5 # points per net vote on a matching tag
  TAG_NET_CAP            = 2   # net votes counted per tag
  TAG_TOTAL_CAP          = 8.0 # ceiling for the whole tag adjustment

  # rating: 1 (more like this), -1 (less like this), 0 (clear)
  def self.upsert_rating(db, album_id:, profile_name:, rating:)
    if rating.zero?
      db[:ratings].where(album_id: album_id, profile_name: profile_name).delete
      return
    end

    db[:ratings].insert_conflict(
      target: %i[album_id profile_name],
      update: { rating: Sequel[:excluded][:rating],
                rated_at: Sequel[:excluded][:rated_at] }
    ).insert(album_id: album_id, profile_name: profile_name,
             rating: rating, rated_at: Time.now)
  end

  # Everything a profile has learned from its ratings: liked/disliked
  # artists, and net votes per tag (tags come from the stored score rows).
  def self.prefs(db, profile_name)
    rows = db[:ratings]
           .where(Sequel[:ratings][:profile_name] => profile_name)
           .join(:albums, id: Sequel[:ratings][:album_id])
           .left_join(:album_scores, album_id: Sequel[:albums][:id],
                                     profile_name: profile_name)
           .select(Sequel[:ratings][:rating],
                   Sequel[:albums][:artist],
                   Sequel[:album_scores][:tags])
           .all

    prefs = { liked_artists: [], disliked_artists: [], tag_affinity: Hash.new(0) }
    rows.each do |row|
      artist = row[:artist].downcase
      row[:rating].positive? ? prefs[:liked_artists] << artist : prefs[:disliked_artists] << artist
      JSON.parse(row[:tags] || '[]').map(&:downcase).uniq.each do |tag|
        prefs[:tag_affinity][tag] += row[:rating]
      end
    end
    prefs
  end

  def self.adjustment(prefs, artist, tags)
    total = 0.0
    key = artist.downcase
    total += ARTIST_LIKE_BOOST if prefs[:liked_artists].include?(key)
    total -= ARTIST_DISLIKE_PENALTY if prefs[:disliked_artists].include?(key)

    tag_adjustment = tags.map(&:downcase).uniq.sum do |tag|
      prefs[:tag_affinity].fetch(tag, 0).clamp(-TAG_NET_CAP, TAG_NET_CAP) * TAG_AFFINITY_STEP
    end
    total + tag_adjustment.clamp(-TAG_TOTAL_CAP, TAG_TOTAL_CAP)
  end

  # Re-rank every stored score for a profile from its saved components
  # plus the current feedback — no Last.fm calls, so it's instant.
  def self.reapply(db, profile_name)
    current = prefs(db, profile_name)

    db[:album_scores]
      .where(Sequel[:album_scores][:profile_name] => profile_name)
      .join(:albums, id: :album_id)
      .select(Sequel[:album_scores][:id].as(:score_id),
              Sequel[:albums][:artist],
              Sequel[:album_scores][:artist_score],
              Sequel[:album_scores][:tag_score],
              Sequel[:album_scores][:metacritic_score],
              Sequel[:album_scores][:tags])
      .all
      .each do |row|
        base = row[:artist_score].to_f + row[:tag_score].to_f + row[:metacritic_score].to_f
        tags = JSON.parse(row[:tags] || '[]')
        total = (base + adjustment(current, row[:artist], tags)).clamp(0.0, 100.0)
        db[:album_scores].where(id: row[:score_id]).update(similarity_score: total)
      end
  end
end
