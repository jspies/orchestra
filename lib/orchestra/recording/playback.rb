module Orchestra
  class Recording
    class Playback < BasicObject
      attr :mocks

      def initialize mocks
        @mocks = mocks
      end

      def respond_to? meth
        mocks.has_key? meth
      end

      def self.build service_recording
        factory = Factory.new
        factory.build service_recording
      end

      class Factory
        attr :klass, :mocks

        def initialize
          @klass = Class.new Playback
          @mocks = Hash.new do |hsh, meth| hsh[meth] = {} end
        end

        def build service_recording
          record = method :<<
          service_recording.each &record
          klass.new mocks
        end

        def << record
          method = record[:method].to_sym
          unless klass.instance_methods.include? method
            klass.send :define_method, method do |*args| mocks[method][args] end
          end
          mocks[method][record[:input]] = record[:output]
        end

        def singleton
          singleton = class << instance ; self end
        end
      end
    end
  end
end
