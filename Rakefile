# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |task|
  task.ruby_opts = %w[-I../tessel/lib -I../glyphic/lib -I../twiddle/lib -I../rbgl/lib -I../larb/lib -I../rlsl/lib]
end

task default: :spec
task verify: :spec
