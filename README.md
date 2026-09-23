# Gesso

[![Gem version](https://badge.fury.io/rb/gesso.svg)](https://rubygems.org/gems/gesso)
[![Downloads](https://img.shields.io/gem/dt/gesso?label=downloads)](https://rubygems.org/gems/gesso)
[![CI](https://github.com/rbgfx/gesso/actions/workflows/main.yml/badge.svg)](https://github.com/rbgfx/gesso/actions/workflows/main.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-750014.svg)](LICENSE.txt)

> Processing-style 2D drawing for Ruby, backed by Tessel and rbgl.

Gesso is a small creative coding DSL for sketches that can run in an rbgl
window or render deterministic PNG frames without a window.

**[Features](#features) · [Installation](#installation) · [Quick start](#quick-start) · [CLI](#cli) · [Development](#development)**

## Features

- Immediate-mode setup and draw callbacks.
- Lines, shapes, images, transforms, text, and configurable stroke styles.
- RGB and HSB color modes with corner, center, and radius shape modes.
- Seeded random values and deterministic smooth noise.
- Optional rlsl shader backgrounds and Twiddle control panels.
- Interactive windows and headless frame rendering.

## Installation

Add Gesso to your Gemfile:

~~~ruby
gem "gesso"
~~~

Then run:

~~~sh
bundle install
~~~

Or install the released gem:

~~~sh
gem install gesso
~~~

## Quick start

~~~ruby
require "gesso"

sketch = Gesso.run(width: 320, height: 200) do
  setup { background 16, 24, 39 }

  draw do
    fill 240, 120, 80
    circle width / 2, height / 2, 30
  end
end

sketch.canvas.write("shot.png")
~~~

For a top-level sketch file, load the automatic DSL:

~~~ruby
require "gesso/auto"

size 320, 200
draw do
  background "#101827"
  fill "#f07850"
  circle 160, 100, 30
end
~~~

## CLI

~~~sh
gesso run examples/bubbles.rb
gesso render examples/bubbles.rb --frames 3 -o frames
~~~

Use <code>--backend file</code> for a headless window run. The
<code>examples/gui_sketch.rb</code> example shows the optional Twiddle panel.

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

## License

[MIT](LICENSE.txt)
