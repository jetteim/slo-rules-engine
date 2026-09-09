# frozen_string_literal: true

# require deduplicates suites also loaded through compatibility entry points.
Dir.glob(File.join(__dir__, '**', '*_test.rb')).sort.each do |path|
  require path unless path == File.expand_path(__FILE__)
end
