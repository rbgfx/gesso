<h1 align="center">Gesso</h1>

<p align="center">Processing-style 2D drawing for Ruby, backed by Tessel and RBGL.</p>

<p align="center">
  <a href="https://rubygems.org/gems/gesso"><img src="https://badge.fury.io/rb/gesso.svg" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/gesso"><img src="https://img.shields.io/gem/dt/gesso?label=downloads" alt="Downloads"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby Version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="License"></a>
</p>

[Features](#features) · [Installation](#installation) · [Quick Start](#quick-start) · [Browser](#browser) · [CLI](#cli)

***

Gesso is a small creative-coding DSL for sketches that run in an RBGL window or render deterministic PNG frames without a window.

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

### Requirements

- Ruby 3.1 or newer.
- A C toolchain is needed when Bundler builds Larb's native extension.

## Quick Start

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

## Browser

Add the Webvas gem to the application bundle to run a sketch in a browser worker. The Webvas playground build includes Gesso and its graphics dependencies.

~~~ruby
require "gesso"

Gesso.run(width: 480, height: 320, runner: :web) do
  background "#171a18"
  draw do
    background "#171a18"
    fill "#d38a62"
    circle 240, 160, 48
  end
end
~~~

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

## Contributing

Bug reports and pull requests are welcome at [rbgfx/gesso](https://github.com/rbgfx/gesso).

## License

[MIT](LICENSE.txt)
