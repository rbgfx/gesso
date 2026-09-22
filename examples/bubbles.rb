# frozen_string_literal: true

size 64, 48
setup { background "#101827" }
draw do
  background "#101827"
  no_stroke
  fill "#f07850"
  circle(20 + frame_count * 2, 24, 8)
end
