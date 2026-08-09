# frozen_string_literal: true

require_relative 'test_helper'

class TestUpsertRating < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
    @album = insert_album!(@db)
  end

  def test_inserts_thumbs_up
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'shoegaze', rating: 1)

    row = @db[:ratings].first
    assert_equal @album[:id], row[:album_id]
    assert_equal 'shoegaze', row[:profile_name]
    assert_equal 1, row[:rating]
    refute_nil row[:rated_at]
  end

  def test_inserts_thumbs_down
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'shoegaze', rating: -1)
    assert_equal(-1, @db[:ratings].first[:rating])
  end

  def test_rerating_updates_in_place
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'shoegaze', rating: 1)
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'shoegaze', rating: -1)

    assert_equal 1, @db[:ratings].count
    assert_equal(-1, @db[:ratings].first[:rating])
  end

  def test_zero_clears_rating
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'shoegaze', rating: 1)
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'shoegaze', rating: 0)

    assert_equal 0, @db[:ratings].count
  end

  def test_profiles_rate_independently
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'shoegaze', rating: 1)
    Feedback.upsert_rating(@db, album_id: @album[:id], profile_name: 'ambient', rating: -1)

    assert_equal 2, @db[:ratings].count
  end
end

class TestFeedbackPrefs < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
  end

  def rate!(artist:, title:, rating:, tags: ['shoegaze'], profile: 'shoegaze')
    album = insert_album!(@db, artist: artist, title: title)
    insert_score!(@db, album_id: album[:id], profile: profile, tags: tags)
    Feedback.upsert_rating(@db, album_id: album[:id], profile_name: profile, rating: rating)
    album
  end

  def test_collects_liked_artists_downcased
    rate!(artist: 'Whirr', title: 'A', rating: 1)

    prefs = Feedback.prefs(@db, 'shoegaze')
    assert_includes prefs[:liked_artists], 'whirr'
    assert_empty prefs[:disliked_artists]
  end

  def test_collects_disliked_artists
    rate!(artist: 'Nickelback', title: 'B', rating: -1)

    prefs = Feedback.prefs(@db, 'shoegaze')
    assert_includes prefs[:disliked_artists], 'nickelback'
  end

  def test_tag_affinity_nets_votes
    rate!(artist: 'A', title: 'X', rating: 1, tags: ['shoegaze', 'noise pop'])
    rate!(artist: 'B', title: 'Y', rating: 1, tags: ['shoegaze'])
    rate!(artist: 'C', title: 'Z', rating: -1, tags: %w[shoegaze metalcore])

    prefs = Feedback.prefs(@db, 'shoegaze')
    assert_equal 1, prefs[:tag_affinity]['shoegaze'] # +1 +1 -1
    assert_equal 1, prefs[:tag_affinity]['noise pop']
    assert_equal(-1, prefs[:tag_affinity]['metalcore'])
  end

  def test_scoped_to_profile
    rate!(artist: 'Whirr', title: 'A', rating: 1, profile: 'other')

    prefs = Feedback.prefs(@db, 'shoegaze')
    assert_empty prefs[:liked_artists]
    assert_empty prefs[:tag_affinity]
  end

  def test_rating_without_score_row_contributes_artist_only
    album = insert_album!(@db, artist: 'Unscored', title: 'NoTags')
    Feedback.upsert_rating(@db, album_id: album[:id], profile_name: 'shoegaze', rating: 1)

    prefs = Feedback.prefs(@db, 'shoegaze')
    assert_includes prefs[:liked_artists], 'unscored'
    assert_empty prefs[:tag_affinity]
  end
end

class TestFeedbackAdjustment < Minitest::Test
  def prefs(liked: [], disliked: [], affinity: {})
    { liked_artists: liked, disliked_artists: disliked,
      tag_affinity: Hash.new(0).merge(affinity) }
  end

  def test_liked_artist_boost
    adj = Feedback.adjustment(prefs(liked: ['whirr']), 'Whirr', [])
    assert_in_delta Feedback::ARTIST_LIKE_BOOST, adj, 0.01
  end

  def test_disliked_artist_penalty
    adj = Feedback.adjustment(prefs(disliked: ['nickelback']), 'Nickelback', [])
    assert_in_delta(-Feedback::ARTIST_DISLIKE_PENALTY, adj, 0.01)
  end

  def test_unknown_artist_no_adjustment
    assert_in_delta 0.0, Feedback.adjustment(prefs, 'Slowdive', []), 0.01
  end

  def test_tag_affinity_positive
    adj = Feedback.adjustment(prefs(affinity: { 'shoegaze' => 1 }), 'New Band', ['Shoegaze'])
    assert_in_delta Feedback::TAG_AFFINITY_STEP, adj, 0.01
  end

  def test_tag_affinity_negative
    adj = Feedback.adjustment(prefs(affinity: { 'metalcore' => -2 }), 'New Band', ['metalcore'])
    assert_in_delta(-2 * Feedback::TAG_AFFINITY_STEP, adj, 0.01)
  end

  def test_per_tag_votes_capped
    adj = Feedback.adjustment(prefs(affinity: { 'shoegaze' => 10 }), 'New Band', ['shoegaze'])
    assert_in_delta Feedback::TAG_NET_CAP * Feedback::TAG_AFFINITY_STEP, adj, 0.01
  end

  def test_total_tag_adjustment_capped
    affinity = { 'a' => 2, 'b' => 2, 'c' => 2, 'd' => 2 } # 4 × 3.0 = 12 → capped at 8
    adj = Feedback.adjustment(prefs(affinity: affinity), 'New Band', %w[a b c d])
    assert_in_delta Feedback::TAG_TOTAL_CAP, adj, 0.01
  end

  def test_artist_and_tags_combine
    p = prefs(liked: ['whirr'], affinity: { 'shoegaze' => 1 })
    adj = Feedback.adjustment(p, 'Whirr', ['shoegaze'])
    assert_in_delta Feedback::ARTIST_LIKE_BOOST + Feedback::TAG_AFFINITY_STEP, adj, 0.01
  end
end

class TestReapplyFeedback < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
    @profile = 'shoegaze'
  end

  def scored_album!(artist:, title:, tags: ['shoegaze'],
                    artist_score: 20.0, tag: 30.0, meta: 25.0)
    album = insert_album!(@db, artist: artist, title: title)
    insert_score!(@db, album_id: album[:id], profile: @profile,
                       similarity: artist_score + tag + meta,
                       artist: artist_score, tag: tag, meta: meta, tags: tags)
    album
  end

  def similarity_of(album)
    @db[:album_scores].where(album_id: album[:id], profile_name: @profile)
                      .first[:similarity_score]
  end

  def test_liking_an_album_boosts_other_albums_by_same_artist
    liked = scored_album!(artist: 'Whirr', title: 'Feels Like You', tags: [])
    other = scored_album!(artist: 'Whirr', title: 'Sway', tags: [])

    Feedback.upsert_rating(@db, album_id: liked[:id], profile_name: @profile, rating: 1)
    Feedback.reapply(@db, @profile)

    # base 75 + artist boost 12
    assert_in_delta 87.0, similarity_of(other), 0.01
  end

  def test_disliking_sinks_the_artist
    hated = scored_album!(artist: 'Nickelback', title: 'Whatever', tags: [])

    Feedback.upsert_rating(@db, album_id: hated[:id], profile_name: @profile, rating: -1)
    Feedback.reapply(@db, @profile)

    # base 75 - penalty 15
    assert_in_delta 60.0, similarity_of(hated), 0.01
  end

  def test_tag_affinity_carries_to_unrelated_artists
    liked  = scored_album!(artist: 'Whirr', title: 'A', tags: ['noise pop'])
    other  = scored_album!(artist: 'Hotline TNT', title: 'B', tags: ['noise pop'])

    Feedback.upsert_rating(@db, album_id: liked[:id], profile_name: @profile, rating: 1)
    Feedback.reapply(@db, @profile)

    # base 75 + tag affinity 1 × 1.5
    assert_in_delta 76.5, similarity_of(other), 0.01
  end

  def test_similarity_clamped_to_100
    liked = scored_album!(artist: 'Whirr', title: 'A',
                          artist_score: 40.0, tag: 35.0, meta: 20.0, tags: ['shoegaze'])

    Feedback.upsert_rating(@db, album_id: liked[:id], profile_name: @profile, rating: 1)
    Feedback.reapply(@db, @profile)

    assert_in_delta 100.0, similarity_of(liked), 0.01
  end

  def test_clearing_rating_restores_base_score
    liked = scored_album!(artist: 'Whirr', title: 'A', tags: [])
    Feedback.upsert_rating(@db, album_id: liked[:id], profile_name: @profile, rating: 1)
    Feedback.reapply(@db, @profile)

    Feedback.upsert_rating(@db, album_id: liked[:id], profile_name: @profile, rating: 0)
    Feedback.reapply(@db, @profile)

    assert_in_delta 75.0, similarity_of(liked), 0.01
  end

  def test_only_touches_the_rated_profile
    album = scored_album!(artist: 'Whirr', title: 'A', tags: [])
    insert_score!(@db, album_id: album[:id], profile: 'other', similarity: 75.0,
                       artist: 20.0, tag: 30.0, meta: 25.0, tags: [])

    Feedback.upsert_rating(@db, album_id: album[:id], profile_name: @profile, rating: 1)
    Feedback.reapply(@db, @profile)

    other = @db[:album_scores].where(album_id: album[:id], profile_name: 'other').first
    assert_in_delta 75.0, other[:similarity_score], 0.01
  end
end
