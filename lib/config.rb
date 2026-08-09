# frozen_string_literal: true

require 'yaml'

DEFAULT_CONFIG_PATH = File.expand_path('../config/taste_profile.yml', __dir__).freeze

def load_taste_profile(path = DEFAULT_CONFIG_PATH)
  unless File.exist?(path)
    raise "Taste profile not found at '#{path}'. " \
          'Copy config/taste_profile.yml.example to config/taste_profile.yml and edit it.'
  end

  YAML.safe_load_file(path, symbolize_names: true).freeze
end

TASTE_PROFILE_PATH = ENV.fetch('SHOEGAZEGAZER_CONFIG', DEFAULT_CONFIG_PATH).freeze
TASTE_PROFILE = load_taste_profile(TASTE_PROFILE_PATH)

# Scores are stored per profile, keyed by the config file's basename —
# running with profiles/ambient.yml keeps its scores separate from the default.
TASTE_PROFILE_NAME = File.basename(TASTE_PROFILE_PATH, '.yml').freeze
