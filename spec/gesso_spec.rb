# frozen_string_literal: true

require "tmpdir"
require "flipbook"

RSpec.describe Gesso do
  it "has a version number" do
    expect(Gesso::VERSION).not_to be nil
  end

  it "runs a headless sketch and draws shapes" do
    sketch = Gesso.run(width: 20, height: 20) do
      setup { background 0 }
      draw do
        fill 255, 0, 0
        rect 2, 2, 5, 5
      end
    end

    expect(sketch.canvas[3, 3]).to eq([255, 0, 0, 255])
    expect(sketch.frame_count).to eq(1)
  end

  it "keeps the transform stack balanced" do
    sketch = Gesso::Sketch.new(width: 10, height: 10)
    expect { sketch.pop }.to raise_error(RuntimeError)
  end

  it "returns independent headless frames and accepts hex colors" do
    sketch = Gesso::Sketch.new(width: 2, height: 1)
    sketch.draw { sketch.background(sketch.frame_count.zero? ? "#ff0000" : "#0000ff") }
    frames = Gesso::Runner::Headless.run(sketch, frames: 2)
    expect(frames.map { |image| image[0, 0] }).to eq([[255, 0, 0, 255], [0, 0, 255, 255]])
  end

  it "records the requested headless frames as a GIF" do
    Dir.mktmpdir do |directory|
      output = File.join(directory, "sketch.gif")
      sketch = Gesso.run(width: 2, height: 1) do
        setup { save_gif(output, frames: 3, fps: 10) }
        draw { background(frame_count.even? ? "#ff0000" : "#0000ff") }
      end

      frames = Flipbook.read(output)
      expect(frames.length).to eq(3)
      expect(frames.map { |frame| frame[0, 0] }).to eq([[255, 0, 0, 255], [0, 0, 255, 255], [255, 0, 0, 255]])
      expect(sketch.gif_frames_remaining).to be_nil
    end
  end

  it "keeps an existing GIF when a recording fails before its requested frames" do
    Dir.mktmpdir do |directory|
      output = File.join(directory, "sketch.gif")
      File.binwrite(output, "original")
      sketch = Gesso::Sketch.new(width: 2, height: 1)
      sketch.setup { sketch.save_gif(output, frames: 3, fps: 10) }
      sketch.draw do
        raise "drawing failed" if sketch.frame_count == 1

        sketch.background("#ff0000")
      end

      expect { Gesso::Runner::Headless.run(sketch, frames: 3) }.to raise_error("drawing failed")
      expect(File.binread(output)).to eq("original")
      expect(Dir.children(directory)).to eq(["sketch.gif"])
    end
  end

  it "transforms rectangle strokes exactly once" do
    sketch = Gesso::Sketch.new(width: 8, height: 8)
    sketch.no_fill
    sketch.stroke("#ff0000")
    sketch.translate(2, 0)
    sketch.rect(1, 1, 2, 2)
    expect(sketch.canvas[3, 1]).to eq([255, 0, 0, 255])
    expect(sketch.canvas[7, 1]).to eq([0, 0, 0, 0])
  end

  it "presents a sketch through rbgl's file backend" do
    sketch = Gesso::Sketch.new(width: 2, height: 2)
    sketch.draw { sketch.background("#123456") }
    Dir.mktmpdir do |dir|
      Gesso::Runner::Window.run(sketch, backend: :file, frames: 2, output_dir: dir)
      expect(Dir[File.join(dir, "*.ppm")].length).to eq(2)
      expect(File.read(File.join(dir, "frame_00001.ppm"))).to include("18 52 86")
    end
  end

  it "runs a browser sketch through webvas' requestAnimationFrame loop" do
    require "rbgl"
    backend_class = Class.new(RBGL::GUI::Backend) do
      attr_reader :presented

      def initialize(width:, height:, **options)
        super(width, height)
        @events = [RBGL::GUI::Event.new(:mouse_press, x: 1, y: 1)]
      end

      def poll_events = [@events.shift].compact
      def present(_framebuffer) = (@presented = @pixels; true)
      def set_pixels(buffer, _width, _height) = (@pixels = buffer; true)
      def should_close? = false
      def close = nil
    end
    webvas = Module.new
    webvas.const_set(:Backend, backend_class)
    captured_window = nil
    webvas.define_singleton_method(:run) do |window, &callback|
      captured_window = window
      window.step(0.0, &callback)
    end
    stub_const("Webvas", webvas)
    $LOADED_FEATURES << "webvas.rb"

    mouse_presses = 0
    sketch = Gesso.run(width: 4, height: 3, runner: :web) do
      mouse_pressed { mouse_presses += 1 }
      background "#123456"
    end

    expect(sketch.frame_count).to eq(1)
    expect(mouse_presses).to eq(1)
    expect(captured_window.backend.presented).to eq(sketch.canvas.bytes)
  ensure
    $LOADED_FEATURES.delete("webvas.rb")
  end

  it "runs setup before a window or headless frame is created" do
    sketch = Gesso::Sketch.new
    sketch.setup { sketch.size(7, 5) }

    expect(sketch.prepare!).to equal(sketch)
    expect([sketch.width, sketch.height]).to eq([7, 5])
    expect(Gesso::Runner::Headless.run(sketch, frames: 1).first.width).to eq(7)
    expect(sketch.frame_count).to eq(1)
  end

  it "overlays a twiddle panel and forwards pointer input between frames" do
    sketch = Gesso::Sketch.new(width: 180, height: 90)
    clicked = []
    sketch.draw { sketch.background("#000000") }
    sketch.gui { |ui| ui.window("Controls") { clicked << ui.button("Go") } }
    sketch.frame
    expect(sketch.canvas[12, 12]).not_to eq([0, 0, 0, 255])
    sketch.handle(type: :mouse_press, x: 20, y: 40)
    sketch.frame
    sketch.handle(type: :mouse_release, x: 20, y: 40)
    sketch.frame
    expect(clicked).to eq([false, false, true])
  end

  it "finishes fractional ellipse strokes after rounding their endpoints" do
    sketch = Gesso::Sketch.new(width: 32, height: 32)
    sketch.circle(16.3, 15.7, 8.2)
    expect(sketch.canvas[16, 8][3]).to eq(255)
  end

  it "dispatches drag events and rejects invalid timing" do
    sketch = Gesso::Sketch.new(width: 4, height: 4)
    dragged = 0
    sketch.mouse_dragged { dragged += 1 }
    sketch.handle(type: :mouse_press, x: 1, y: 1)
    sketch.handle(type: :mouse_move, x: 2, y: 2)

    expect(dragged).to eq(1)
    expect { sketch.frame_rate(0) }.to raise_error(ArgumentError)
    expect { sketch.frame_rate(Float::INFINITY) }.to raise_error(ArgumentError)
    expect { sketch.size(0, 4) }.to raise_error(ArgumentError)
  end

  it "provides deterministic bounded noise" do
    sketch = Gesso::Sketch.new(seed: 7)
    first = sketch.noise(1.25, 2.5, 3.75)
    expect(first).to be_between(0.0, 1.0)
    expect(sketch.noise(1.25, 2.5, 3.75)).to eq(first)
    sketch.noise_seed(8)
    expect(sketch.noise(1.25, 2.5, 3.75)).not_to eq(first)
  end

  it "supports RGB and HSB color ranges" do
    sketch = Gesso::Sketch.new(width: 1, height: 1)
    sketch.color_mode(:hsb, 360, 100, 100)
    sketch.background(0, 100, 100)
    expect(sketch.canvas[0, 0]).to eq([255, 0, 0, 255])
    sketch.background(120, 100, 100)
    expect(sketch.canvas[0, 0]).to eq([0, 255, 0, 255])
    sketch.color_mode(:rgb, 1, 1, 1, 1)
    sketch.background(0.5, 0.25, 1.0, 0.5)
    expect(sketch.canvas[0, 0]).to eq([128, 64, 255, 128])
    sketch.color_mode(:rgb, 255)
    sketch.background(32, 128)
    expect(sketch.canvas[0, 0]).to eq([32, 32, 32, 128])
    expect { sketch.color_mode(:cmyk) }.to raise_error(ArgumentError)
    expect { sketch.color_mode(:rgb, 0) }.to raise_error(ArgumentError)
    expect { sketch.color_mode(:rgb, Float::INFINITY) }.to raise_error(ArgumentError)
  end

  it "supports rectangle and ellipse coordinate modes" do
    sketch = Gesso::Sketch.new(width: 10, height: 10)
    sketch.no_stroke
    sketch.fill(255, 0, 0)
    sketch.rect_mode(:center)
    sketch.rect(5, 5, 4, 4)
    expect(sketch.canvas[3, 3]).to eq([255, 0, 0, 255])
    sketch.background(0)
    sketch.ellipse_mode(:radius)
    sketch.ellipse(5, 5, 2, 1)
    expect(sketch.canvas[5, 5]).to eq([255, 0, 0, 255])
    expect { sketch.rect_mode(:radius) }.to raise_error(ArgumentError)
    expect { sketch.ellipse_mode(:corner) }.not_to raise_error
  end

  it "applies stroke weight and honors no_stroke for points" do
    sketch = Gesso::Sketch.new(width: 12, height: 12)
    sketch.no_fill
    sketch.stroke("#ff0000")
    sketch.stroke_weight(3)
    sketch.line(2, 6, 9, 6)
    expect(sketch.canvas[5, 7]).to eq([255, 0, 0, 255])
    expect(sketch.canvas[5, 5]).to eq([255, 0, 0, 255])

    sketch.background(0)
    sketch.no_stroke
    sketch.point(5, 5)
    expect(sketch.canvas[5, 5]).to eq([0, 0, 0, 255])
  end

  it "scales and aligns text" do
    sketch = Gesso::Sketch.new(width: 40, height: 24)
    sketch.fill(255)
    sketch.text_size(18)
    expect(sketch.text_width("A")).to be > 4
    sketch.text_align(:center, :center)
    sketch.text("A", 20, 12)

    expect(sketch.canvas.bytes.bytes.any?(&:positive?)).to be(true)
    expect { sketch.text_size(0) }.to raise_error(ArgumentError)
    expect { sketch.text_align(:middle) }.to raise_error(ArgumentError)
  end

  it "accepts square stroke caps and joins" do
    sketch = Gesso::Sketch.new
    expect { sketch.stroke_cap(:square) }.not_to raise_error
    expect { sketch.stroke_join(:square) }.not_to raise_error
    expect { sketch.stroke_cap(:butt) }.to raise_error(ArgumentError)
  end

  it "leaves open shapes unclosed" do
    sketch = Gesso::Sketch.new(width: 8, height: 8)
    sketch.no_fill
    sketch.begin_shape
    sketch.vertex(1, 1)
    sketch.vertex(6, 1)
    sketch.vertex(6, 6)
    sketch.end_shape(close: false)

    expect(sketch.canvas[1, 6]).to eq([0, 0, 0, 0])
    expect(sketch.canvas[6, 1]).to eq([0, 0, 0, 255])
  end

  it "renders and caches shader backgrounds" do
    sketch = Gesso::Sketch.new(width: 2, height: 2)
    sketch.instance_eval do
      draw do
        shader_background(:gradient) do |frag_coord, resolution, _uniforms|
          vec3(frag_coord.y / resolution.y, 0.0, 0.0)
        end
      end
    end

    first = sketch.frame
    expect(first[0, 0][0]).to be > first[0, 1][0]
    shader = sketch.instance_variable_get(:@shader_cache).fetch(:gradient)
    sketch.frame
    expect(sketch.instance_variable_get(:@shader_cache).fetch(:gradient)).to equal(shader)
  end
end
