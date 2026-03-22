# frozen_string_literal: true

require 'yaml'

DEFAULT_CONFIG_PATH = File.expand_path('../../config/taste_profile.yml', __FILE__).freeze

def load_taste_profile(path = DEFAULT_CONFIG_PATH)
  unless File.exist?(path)
    raise "Taste profile not found at '#{path}'. " \
          'Copy config/taste_profile.yml.example to config/taste_profile.yml and edit it.'
  end

  YAML.safe_load(File.read(path), symbolize_names: true).freeze
end

TASTE_PROFILE = load_taste_profile(ENV.fetch('SHOEGAZEGAZER_CONFIG', DEFAULT_CONFIG_PATH))
