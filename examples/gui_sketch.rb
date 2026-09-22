# frozen_string_literal: true

require "gesso/auto"

size 320, 200
speed = 1.0

draw do
  background "#101827"
  fill "#f07850"
  circle 160 + Math.sin(frame_count * 0.05 * speed) * 80, 100, 24
end

gui do |ui|
  ui.window("Controls") do
    speed = ui.slider("Speed", speed, 0.0..4.0)
  end
end
