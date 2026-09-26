# frozen_string_literal: true

require "tessel"
require "tempfile"

require_relative "gesso/version"

module Gesso
  class Error < StandardError; end

  class Sketch
    attr_reader :canvas, :width, :height, :frame_count, :mouse_x, :mouse_y, :key

    def initialize(width: 640, height: 480, seed: Random.new_seed)
      @width = width
      @height = height
      @canvas = Tessel::Image.new(width, height)
      @random = Random.new(seed)
      @noise_seed = seed
      @frame_count = 0
      @mouse_x = @mouse_y = 0
      @pmouse_x = @pmouse_y = 0
      @pressed = false
      @fill = Tessel::Color.pack([255, 255, 255, 255])
      @stroke = Tessel::Color.pack([0, 0, 0, 255])
      @color_mode = :rgb
      @color_ranges = [255.0, 255.0, 255.0, 255.0]
      @rect_mode = :corner
      @ellipse_mode = :corner
      @fill_enabled = true
      @stroke_enabled = true
      @stroke_weight = 1
      @stroke_cap = :round
      @stroke_join = :round
      @text_align = [:left, :top]
      @matrix = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
      @matrices = []
      @draw_block = nil
      @setup_block = nil
      @setup_ran = false
      @handlers = Hash.new { |hash, key| hash[key] = [] }
      @ui_events = []
      @shader_cache = {}
    end

    def size(width, height)
      width = Integer(width)
      height = Integer(height)
      raise ArgumentError, "size must be positive" unless width.positive? && height.positive?
      @width, @height = width, height
      @canvas = Tessel::Image.new(width, height)
    end

    def setup(&block) = (@setup_block = block)
    def draw(&block) = (@draw_block = block)
    def gui(&block) = (@gui_block = block)

    def prepare!
      return self if @setup_ran

      @setup_ran = true
      @setup_block&.call
      self
    end
    def shader_background(name = nil, &block)
      raise ArgumentError, "shader_background requires a block" unless block

      require "rlsl"
      key = name || block.source_location
      shader = (@shader_cache[key] ||= begin
        builder = RLSL::ShaderBuilder.new(:"gesso_#{@shader_cache.length}")
        builder.uniforms { float :time; vec4 :mouse }
        builder.fragment(&block)
        builder.compile_and_load
      end)
      buffer = "\0".b * (@width * @height * 4)
      shader.render(buffer, @width, @height, time: millis / 1000.0, mouse: [@mouse_x.to_f, (@height - @mouse_y).to_f, 0.0, 0.0])
      rgba = buffer.bytes.each_slice(4).flat_map { |blue, green, red, alpha| [red, green, blue, alpha] }.pack("C*")
      @canvas = Tessel::Image.from_rgba(@width, @height, rgba)
    end
    def key_pressed(&block) = @handlers[:key_pressed] << block
    def key_released(&block) = @handlers[:key_released] << block
    def mouse_pressed(&block) = @handlers[:mouse_pressed] << block
    def mouse_released(&block) = @handlers[:mouse_released] << block
    def mouse_moved(&block) = @handlers[:mouse_moved] << block
    def mouse_dragged(&block) = @handlers[:mouse_dragged] << block

    def frame
      prepare!
      @draw_block&.call
      if @gui_block
        require "twiddle"
        require "glyphic"
        @ui ||= Twiddle::Context.new(font: Glyphic.default)
        @ui.frame(events: @ui_events) { |context| @gui_block.call(context) }
        @ui.render(@canvas)
        @ui_events.clear
      end
      @frame_count += 1
      record_gif_frame
      @canvas
    end

    def handle(event)
      @ui_events << event if @gui_block
      case event[:type]&.to_sym
      when :mouse_move
        @pmouse_x, @pmouse_y, @mouse_x, @mouse_y = @mouse_x, @mouse_y, event[:x], event[:y]
        @handlers[:mouse_moved].each(&:call)
        @handlers[:mouse_dragged].each(&:call) if @pressed
      when :mouse_press then @pressed = true; @handlers[:mouse_pressed].each(&:call)
      when :mouse_release then @pressed = false; @handlers[:mouse_released].each(&:call)
      when :key_press then @key = event[:key]; @handlers[:key_pressed].each(&:call)
      when :key_release then @key = event[:key]; @handlers[:key_released].each(&:call)
      end
    end

    def background(*args)
      @canvas.clear(color(*args))
    end

    def color_mode(mode = :rgb, max1 = 255, max2 = max1, max3 = max1, max_alpha = 255)
      mode = mode.to_sym
      raise ArgumentError, "color mode must be :rgb or :hsb" unless %i[rgb hsb].include?(mode)
      ranges = [max1, max2, max3, max_alpha].map(&:to_f)
      raise ArgumentError, "color ranges must be finite and positive" unless ranges.all? { |range| range.finite? && range.positive? }
      @color_mode = mode
      @color_ranges = ranges
    end

    def fill(*args) = (@fill_enabled = true; @fill = color(*args))
    def no_fill = (@fill_enabled = false)
    def stroke(*args) = (@stroke_enabled = true; @stroke = color(*args))
    def no_stroke = (@stroke_enabled = false)
    def stroke_weight(value) = (@stroke_weight = [value.to_f, 1].max)
    def stroke_cap(mode)
      mode = mode.to_sym
      raise ArgumentError, "stroke cap must be :round or :square" unless %i[round square].include?(mode)
      @stroke_cap = mode
    end
    def stroke_join(mode)
      mode = mode.to_sym
      raise ArgumentError, "stroke join must be :round or :square" unless %i[round square].include?(mode)
      @stroke_join = mode
    end
    def mouse_pressed? = @pressed
    def pmouse_x = @pmouse_x
    def pmouse_y = @pmouse_y
    def frame_rate(value = nil)
      return (@frame_rate || 60.0) unless value
      value = value.to_f
      raise ArgumentError, "frame rate must be finite and positive" unless value.finite? && value.positive?
      @frame_rate = value
    end
    def millis = (@frame_count * 1000.0 / frame_rate).round

    def point(x, y)
      draw_line(x, y, x, y, @stroke) if @stroke_enabled
    end

    def line(x1, y1, x2, y2)
      draw_line(x1, y1, x2, y2, @stroke) if @stroke_enabled
    end

    def rect(x, y, width, height)
      x, y = x - width / 2.0, y - height / 2.0 if @rect_mode == :center
      polygon([[x, y], [x + width, y], [x + width, y + height], [x, y + height]])
    end

    def rect_mode(mode)
      mode = mode.to_sym
      raise ArgumentError, "rect mode must be :corner or :center" unless %i[corner center].include?(mode)
      @rect_mode = mode
    end

    def square(x, y, size) = rect(x, y, size, size)

    def ellipse(x, y, width, height)
      case @ellipse_mode
      when :center then x, y = x - width / 2.0, y - height / 2.0
      when :radius then width, height = width * 2.0, height * 2.0; x, y = x - width / 2.0, y - height / 2.0
      end
      cx = x + width / 2.0
      cy = y + height / 2.0
      rx = width / 2.0
      ry = height / 2.0
      return if rx <= 0 || ry <= 0
      unless @matrix == [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        count = [((2 * Math::PI * [rx, ry].max) / 2).ceil, 16].max
        return polygon(count.times.map { |index| angle = index * 2 * Math::PI / count; [cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry] })
      end
      ([(y).floor, 0].max..[(y + height).ceil, @height - 1].min).each do |row|
        dy = (row + 0.5 - cy) / ry
        next if dy.abs > 1
        half = (rx * Math.sqrt(1 - dy * dy)).floor
        @canvas.hspan((cx - half).floor, (cx + half).floor, row, @fill, blend: @fill.getbyte(3) == 255 ? :copy : :alpha) if @fill_enabled
      end
      ellipse_outline(cx, cy, rx, ry) if @stroke_enabled
    end

    def circle(x, y, radius)
      case @ellipse_mode
      when :corner then ellipse(x - radius, y - radius, radius * 2, radius * 2)
      when :center then ellipse(x, y, radius * 2, radius * 2)
      when :radius then ellipse(x, y, radius, radius)
      end
    end

    def ellipse_mode(mode)
      mode = mode.to_sym
      raise ArgumentError, "ellipse mode must be :corner, :center, or :radius" unless %i[corner center radius].include?(mode)
      @ellipse_mode = mode
    end

    def triangle(*points) = polygon(points.each_slice(2).to_a)
    def quad(*points) = polygon(points.each_slice(2).to_a)

    def begin_shape
      @shape = []
    end

    def vertex(x, y)
      @shape << [x, y]
    end

    def end_shape(close: true)
      points = @shape
      if close
        polygon(points)
      elsif @stroke_enabled
        points.each_cons(2) { |first, second| draw_line(*first, *second, @stroke) }
      end
      @shape = nil
    end

    def arc(x, y, width, height, start_angle, stop_angle)
      count = [(stop_angle - start_angle).abs * [width, height].max / 4, 8].max.to_i
      points = (0..count).map do |index|
        angle = start_angle + (stop_angle - start_angle) * index / count
        [x + Math.cos(angle) * width / 2, y + Math.sin(angle) * height / 2]
      end
      polygon(points)
    end

    def push = @matrices << @matrix.dup
    def pop
      raise RuntimeError, "transform stack is empty" if @matrices.empty?
      @matrix = @matrices.pop
    end
    def reset_matrix = (@matrix = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
    def translate(x, y) = multiply_matrix([1, 0, 0, 1, x, y])
    def scale(x, y = x) = multiply_matrix([x, 0, 0, y, 0, 0])
    def rotate(angle) = multiply_matrix([Math.cos(angle), Math.sin(angle), -Math.sin(angle), Math.cos(angle), 0, 0])

    def random_seed(seed) = (@random = Random.new(seed))
    def random(maximum = 1, maximum2 = nil) = maximum2 ? @random.rand(maximum.to_f...maximum2.to_f) : @random.rand(maximum.to_f)
    def noise_seed(seed) = (@noise_seed = Integer(seed))
    def noise(x, y = 0, z = 0)
      coordinates = [x, y, z].map(&:to_f)
      base = coordinates.map(&:floor)
      fraction = coordinates.each_with_index.map { |value, index| smooth(value - base[index]) }
      layers = [0, 1].product([0, 1], [0, 1]).map do |offsets|
        noise_value(*base.zip(offsets).map { |value, offset| value + offset })
      end
      x0 = interpolate(layers[0], layers[4], fraction[0])
      x1 = interpolate(layers[1], layers[5], fraction[0])
      x2 = interpolate(layers[2], layers[6], fraction[0])
      x3 = interpolate(layers[3], layers[7], fraction[0])
      y0 = interpolate(x0, x2, fraction[1])
      y1 = interpolate(x1, x3, fraction[1])
      interpolate(y0, y1, fraction[2])
    end
    def map(value, start1, stop1, start2, stop2) = start2 + (value - start1).to_f / (stop1 - start1) * (stop2 - start2)
    def lerp(start, stop, amount) = start + (stop - start) * amount
    def constrain(value, minimum, maximum) = [[value, minimum].max, maximum].min
    def dist(x1, y1, x2, y2) = Math.hypot(x2 - x1, y2 - y1)
    def degrees(radians) = radians * 180 / Math::PI
    def radians(degrees) = degrees * Math::PI / 180

    def image(source, x, y, width = nil, height = nil)
      source = source.scale_nearest(width, height) if width && height
      @canvas.blit(source, x, y, blend: :alpha)
    end

    def load_image(path) = Tessel.read(path)
    def save(path) = @canvas.write(path)
    def save_gif(path, frames: 120, fps: frame_rate, loop: true)
      raise ArgumentError, "a GIF recording is already active" if @gif_recorder
      raise TypeError, "frames must be an Integer" unless frames.is_a?(Integer)
      raise ArgumentError, "frames must be positive" unless frames.positive?

      rate = Float(fps)
      raise ArgumentError, "fps must be finite and positive" unless rate.finite? && rate.positive?
      begin
        require "flipbook"
      rescue LoadError => error
        raise LoadError, "Gesso#save_gif requires the optional flipbook gem", cause: error
      end
      target = File.expand_path(path)
      mode = File.exist?(target) ? File.stat(target).mode & 0o777 : 0o666 & ~File.umask
      io = Tempfile.new(".gesso-", File.dirname(target))
      io.binmode
      writer = Flipbook::GIF::Writer.new(io, width: @width, height: @height, loop:, palette: :per_frame)
      @gif_recorder = { writer:, io:, target:, mode:, remaining: frames, delay: Rational(1, rate.to_s) }
      path
    rescue Exception
      io&.close!
      raise
    end
    def gif_frames_remaining = @gif_recorder&.fetch(:remaining)

    def close(discard: false)
      recorder = @gif_recorder
      @gif_recorder = nil
      return unless recorder
      return recorder[:io].close! if discard

      recorder[:writer].close
      recorder[:io].close
      File.chmod(recorder[:mode], recorder[:io].path)
      File.rename(recorder[:io].path, recorder[:target])
    rescue Exception
      recorder&.fetch(:io)&.close!
      raise
    end
    def get(x, y) = @canvas[x, y]
    def set(x, y, value) = @canvas[x, y] = value

    def text(value, x, y, color: @fill)
      require "glyphic"
      font = @font || Glyphic.default
      value = value.to_s
      scale = @font_size ? @font_size.to_f / font.line_height : 1.0
      if scale == 1.0 && @text_align == [:left, :top]
        font.draw(@canvas, x, y, value, color: color)
        return
      end
      image = font.render(value, color: color)
      image = image.scale_nearest([(image.width * scale).round, 1].max, [(image.height * scale).round, 1].max) if scale != 1.0
      draw_x = x - (@text_align[0] == :center ? image.width / 2.0 : @text_align[0] == :right ? image.width : 0)
      draw_y = case @text_align[1]
      when :center then y - image.height / 2.0
      when :bottom then y - image.height
      when :baseline then y - (@font || Glyphic.default).ascent * scale
      else y
      end
      @canvas.blit(image, draw_x.round, draw_y.round, blend: :alpha)
    end
    def text_font(path, size: nil)
      require "glyphic"
      @font_size = size.to_f if size
      @font = Glyphic.load(path, size: size || 16)
    end
    def text_align(horizontal = :left, vertical = :top)
      horizontal = horizontal.to_sym
      vertical = vertical.to_sym
      raise ArgumentError, "text horizontal alignment must be :left, :center, or :right" unless %i[left center right].include?(horizontal)
      raise ArgumentError, "text vertical alignment must be :top, :center, :bottom, or :baseline" unless %i[top center bottom baseline].include?(vertical)
      @text_align = [horizontal, vertical]
    end
    def text_size(size)
      size = Float(size)
      raise ArgumentError, "text size must be positive" unless size.positive?
      @font_size = size
    end
    def text_width(value)
      require "glyphic"
      font = @font || Glyphic.default
      width = font.text_width(value.to_s)
      @font_size ? (width * @font_size / font.line_height).round : width
    end

    private

    def record_gif_frame
      return unless @gif_recorder

      @gif_recorder[:writer].add(@canvas, delay: @gif_recorder[:delay])
      @gif_recorder[:remaining] -= 1
      close if @gif_recorder[:remaining].zero?
    end

    def color(*args)
      args = args.first if args.length == 1 && args.first.is_a?(Array)
      return Tessel::Color.pack(args) if args.is_a?(String)
      args = [args] if args.is_a?(Numeric)
      args = Array(args)
      return Tessel::Color.pack(args.first) if args.length == 1 && args.first.is_a?(String)
      raise ArgumentError, "color needs 1 to 4 channels" unless (1..4).cover?(args.length)
      alpha = args.length == 2 ? args[1] : (args.length == 4 ? args.pop : @color_ranges[3])
      channels = args.length <= 2 ? [args[0]] * 3 : args
      channels = if @color_mode == :hsb
        hsb_to_rgb(channels).map { |value| (value * 255.0).round }
      else
        channels.each_with_index.map { |value, index| scale_color(value, @color_ranges[index]) }
      end
      channels << scale_color(alpha, @color_ranges[3])
      Tessel::Color.pack(channels)
    end

    def multiply_matrix(other)
      a, b, c, d, e, f = @matrix
      oa, ob, oc, od, oe, of = other
      @matrix = [a * oa + c * ob, b * oa + d * ob, a * oc + c * od, b * oc + d * od, a * oe + c * of + e, b * oe + d * of + f]
    end

    def smooth(value) = value * value * (3 - 2 * value)

    def interpolate(first, second, amount) = first + (second - first) * amount

    def noise_value(x, y, z)
      value = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719 + @noise_seed * 0.12345) * 43_758.5453
      value - value.floor
    end

    def scale_color(value, maximum)
      [[Float(value) / maximum * 255.0, 0.0].max, 255.0].min.round
    end

    def hsb_to_rgb(channels)
      hue, saturation, brightness = channels.map.with_index { |value, index| Float(value) / @color_ranges[index] }
      saturation = [[saturation, 0.0].max, 1.0].min
      brightness = [[brightness, 0.0].max, 1.0].min
      return [brightness, brightness, brightness] if saturation.zero?

      hue = (hue % 1.0) * 6.0
      sector = hue.floor
      fraction = hue - sector
      low = brightness * (1.0 - saturation)
      down = brightness * (1.0 - saturation * fraction)
      up = brightness * (1.0 - saturation * (1.0 - fraction))
      case sector
      when 0 then [brightness, up, low]
      when 1 then [down, brightness, low]
      when 2 then [low, brightness, up]
      when 3 then [low, down, brightness]
      when 4 then [up, low, brightness]
      else [brightness, low, down]
      end
    end

    def transform(point)
      a, b, c, d, e, f = @matrix
      [a * point[0] + c * point[1] + e, b * point[0] + d * point[1] + f]
    end

    def polygon(points)
      return if points.length < 3
      points = points.map { |point| transform(point) }
      min_y = [[points.map(&:last).min.floor, 0].max, @height - 1].min
      max_y = [[points.map(&:last).max.ceil, 0].max, @height - 1].min
      edges = points.each_cons(2).to_a + [[points[-1], points[0]]]
      (min_y..max_y).each do |y|
        intersections = edges.filter_map do |first, second|
          next if first[1] == second[1] || y + 0.5 < [first[1], second[1]].min || y + 0.5 >= [first[1], second[1]].max
          first[0] + (y + 0.5 - first[1]) * (second[0] - first[0]) / (second[1] - first[1])
        end.sort
        intersections.each_slice(2) { |left, right| @canvas.hspan(left.ceil, right.floor - 1, y, @fill, blend: @fill.getbyte(3) == 255 ? :copy : :alpha) if @fill_enabled && right }
      end
      edges.each { |first, second| draw_line(*first, *second, @stroke, transformed: true) if @stroke_enabled }
    end

    def draw_line(x1, y1, x2, y2, color, transformed: false)
      first = transformed ? [x1, y1] : transform([x1, y1])
      last = transformed ? [x2, y2] : transform([x2, y2])
      if @stroke_cap == :square && first != last
        radius = @stroke_weight / 2.0
        length = Math.hypot(last[0] - first[0], last[1] - first[1])
        unit = [(last[0] - first[0]) / length, (last[1] - first[1]) / length]
        first = [first[0] - unit[0] * radius, first[1] - unit[1] * radius]
        last = [last[0] + unit[0] * radius, last[1] + unit[1] * radius]
      end
      x, y = first.map(&:round)
      target_x, target_y = last.map(&:round)
      dx = (target_x - x).abs
      sx = x < target_x ? 1 : -1
      dy = -(target_y - y).abs
      sy = y < target_y ? 1 : -1
      error = dx + dy
      loop do
        if @stroke_weight <= 1
          @canvas[x, y] = color if x.between?(0, @width - 1) && y.between?(0, @height - 1)
        else
          radius = @stroke_weight / 2.0
          ((y - radius).ceil..(y + radius).floor).each do |row|
            distance = @stroke_join == :square ? radius : Math.sqrt([radius * radius - (row - y) ** 2, 0].max)
            @canvas.hspan((x - distance).ceil, (x + distance).floor, row, color, blend: color.getbyte(3) == 255 ? :copy : :alpha)
          end
        end
        break if x == target_x && y == target_y
        twice = 2 * error
        if twice >= dy then error += dy; x += sx end
        if twice <= dx then error += dx; y += sy end
      end
    end

    def ellipse_outline(cx, cy, rx, ry)
      points = 32.times.map { |index| angle = index * 2 * Math::PI / 32; [cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry] }
      points.each_cons(2) { |first, second| draw_line(*first, *second, @stroke) }
      draw_line(*points[-1], *points[0], @stroke)
    end
  end

  module Runner
    class Headless
      def self.run(sketch, frames: nil)
        sketch.prepare!
        frames ||= sketch.gif_frames_remaining || 1
        images = Array.new(frames) { sketch.frame.dup }
        completed = true
        images
      ensure
        sketch.close(discard: !completed)
      end
    end

    class Window
      def self.run(sketch, backend: :auto, frames: nil, output_dir: ".")
        require "rbgl"
        sketch.prepare!
        options = backend.to_sym == :file ? { format: :ppm, max_frames: frames || 1, output_dir: output_dir } : {}
        window = RBGL::GUI::Window.new(width: sketch.width, height: sketch.height, title: "gesso", backend: backend, **options)
        until window.should_close?
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          Array(window.poll_events_raw).each { |event| sketch.handle(event) }
          window.set_pixels(sketch.frame.bytes)
          delay = 1.0 / sketch.frame_rate - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
          sleep(delay) if delay.positive? && backend.to_sym != :file
        end
        completed = true
      ensure
        window&.close
        sketch.close(discard: !completed)
      end
    end

    class Web
      EVENTS = %i[mouse_press mouse_release mouse_move key_press key_release scroll resize].freeze

      def self.run(sketch, canvas: "#screen", pixelated: false)
        require "webvas"
        require "rbgl"
        sketch.prepare!
        backend = Webvas::Backend.new(width: sketch.width, height: sketch.height, canvas:, pixelated:)
        window = RBGL::GUI::Window.new(width: sketch.width, height: sketch.height, backend:)
        EVENTS.each { |type| window.on(type) { |event| sketch.handle(event.to_h) } }
        Webvas.run(window) { sketch_frame = sketch.frame; window.set_pixels(sketch_frame.bytes) }
      end
    end
  end

  module_function

  def run(width: 640, height: 480, seed: Random.new_seed, runner: :headless, canvas: "#screen", pixelated: false, &block)
    sketch = Sketch.new(width: width, height: height, seed: seed)
    sketch.instance_eval(&block)
    case runner.to_sym
    when :headless then Runner::Headless.run(sketch)
    when :window then Runner::Window.run(sketch)
    when :web then Runner::Web.run(sketch, canvas:, pixelated:)
    else raise ArgumentError, "unknown Gesso runner: #{runner}"
    end
    sketch
  end
end
