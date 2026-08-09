# frozen_string_literal: true

require_relative 'test_helper'

class TestScorerUpsertScore < Minitest::Test
  include TestDBHelper

  def setup
    @db = create_test_db
    @album = insert_album!(@db)
    @breakdown = { total: 78.5, artist_score: 35.0, tag_score: 28.0, metacritic_score: 15.5 }
    @tags = ['shoegaze', 'dream pop', 'noise pop']
  end

  def test_inserts_new_score
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'taste_profile',
                             breakdown: @breakdown, tags: @tags)

    row = @db[:album_scores].first
    assert_equal @album[:id], row[:album_id]
    assert_equal 'taste_profile', row[:profile_name]
    assert_in_delta 78.5, row[:similarity_score], 0.01
    assert_in_delta 35.0, row[:artist_score], 0.01
    assert_in_delta 28.0, row[:tag_score], 0.01
    assert_in_delta 15.5, row[:metacritic_score], 0.01
  end

  def test_stores_tags_as_json
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'taste_profile',
                             breakdown: @breakdown, tags: @tags)

    row = @db[:album_scores].first
    parsed = JSON.parse(row[:tags])
    assert_equal ['shoegaze', 'dream pop', 'noise pop'], parsed
  end

  def test_sets_scored_at
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'taste_profile',
                             breakdown: @breakdown, tags: @tags)

    row = @db[:album_scores].first
    refute_nil row[:scored_at]
    # scored_at should be recent (within last few seconds)
    assert_in_delta Time.now.to_f, row[:scored_at].to_f, 5.0
  end

  def test_similarity_score_equals_breakdown_total
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'taste_profile',
                             breakdown: { total: 91.2, artist_score: 40.0,
                                          tag_score: 35.0, metacritic_score: 16.2 },
                             tags: [])

    assert_in_delta 91.2, @db[:album_scores].first[:similarity_score], 0.01
  end

  def test_updates_all_fields_on_conflict
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'taste_profile',
                             breakdown: @breakdown, tags: @tags)

    new_breakdown = { total: 92.0, artist_score: 40.0, tag_score: 35.0, metacritic_score: 17.0 }
    new_tags = ['shoegaze', 'dream pop', 'ambient']
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'taste_profile',
                             breakdown: new_breakdown, tags: new_tags)

    assert_equal 1, @db[:album_scores].count
    row = @db[:album_scores].first
    assert_in_delta 92.0, row[:similarity_score], 0.01
    assert_in_delta 40.0, row[:artist_score], 0.01
    assert_in_delta 35.0, row[:tag_score], 0.01
    assert_in_delta 17.0, row[:metacritic_score], 0.01
    assert_equal new_tags, JSON.parse(row[:tags])
  end

  def test_different_profiles_coexist_for_same_album
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'profile_a',
                             breakdown: @breakdown, tags: @tags)
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'profile_b',
                             breakdown: @breakdown.merge(total: 60.0), tags: ['ambient'])

    assert_equal 2, @db[:album_scores].where(album_id: @album[:id]).count

    a = @db[:album_scores].where(profile_name: 'profile_a').first
    b = @db[:album_scores].where(profile_name: 'profile_b').first
    assert_in_delta 78.5, a[:similarity_score], 0.01
    assert_in_delta 60.0, b[:similarity_score], 0.01
  end

  def test_empty_tags_stored_as_empty_json_array
    Scorer.upsert_score(@db, album_id: @album[:id], profile_name: 'taste_profile',
                             breakdown: @breakdown, tags: [])

    row = @db[:album_scores].first
    assert_equal [], JSON.parse(row[:tags])
  end
end
