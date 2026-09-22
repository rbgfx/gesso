# frozen_string_literal: true

require_relative "../gesso"

module Gesso
  module Auto
    @sketch = Sketch.new
    class << self
      attr_reader :sketch

      def sync!
        target = TOPLEVEL_BINDING.eval("self")
        %i[setup draw].each do |name|
          next unless @sketch.instance_variable_get(:"@#{name}_block").nil?

          method = target.method(name)
          next if method.owner == Gesso::Auto

          @sketch.public_send(name) { target.__send__(name) }
        rescue NameError
          nil
        end
        @sketch
      end
    end

    def method_missing(name, *args, &block)
      sketch = Gesso::Auto.sketch
      return super unless sketch.respond_to?(name)
      sketch.public_send(name, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      Gesso::Auto.sketch.respond_to?(name) || super
    end
  end
end

TOPLEVEL_BINDING.eval("self").extend(Gesso::Auto)
