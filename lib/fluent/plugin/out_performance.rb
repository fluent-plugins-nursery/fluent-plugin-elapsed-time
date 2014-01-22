module Fluent
  class PerformanceOutput < MultiOutput
    Plugin.register_output('performance', self)

    config_param :tag, :string, :default => 'performance'
    config_param :interval, :time, :default => 60
    config_param :each, :default => :es do |val|
      case val.downcase
      when 'es'
        :es
      when 'message'
        :message
      else
        raise ConfigError, "out_performance: each should be 'es' or 'message'"
      end
    end 

    def initialize
      super
      @outputs = []
      @elapsed = []
    end

    attr_reader :outputs, :elapsed

    def configure(conf)
      super
      conf.elements.select {|e|
        e.name == 'store'
      }.each {|e|
        type = e['type']
        unless type
          raise ConfigError, "Missing 'type' parameter on <store> directive"
        end
        $log.debug "adding store type=#{type.dump}"

        output = Plugin.new_output(type)
        output.configure(e)
        @outputs << output
      }
    end

    def start
      @outputs.each {|o|
        o.start
      }
      @thread = Thread.new(&method(:run))
    end

    def shutdown
      @outputs.each {|o|
        o.shutdown
      }
      @thread.terminate
      @thread.join
    end

    def run
      @last_checked ||= Engine.now
      while (sleep 0.1)
        now = Engine.now
        if now - @last_checked >= @interval
          flush_emit
          @last_checked = now
        end
      end
    end

    def flush_emit
      elapsed, @elapsed = @elapsed, []
      unless elapsed.empty?
        max = elapsed.max
        num = elapsed.size
        avg = elapsed.inject(:+) / num.to_f
        Engine.emit(@tag, Engine.now, {:max => max, :avg => avg, :num => num})
      end
    end

    def measure_time(&blk)
      t = Time.now
      output = yield
      @elapsed << (Time.now - t).to_f
      output
    end

    def emit(tag, es, chain)
      if @each == :message
        es.each do |time, record|
          measure_time {
            @outputs.each do |output|
              output.emit(tag, OneEventStream.new(time, record), NullOutputChain.instance)
            end
          }
        end
      else
        measure_time {
          @outputs.each do |output|
            output.emit(tag, es, NullOutputChain.instance)
          end
        }
      end
      chain.next
    end
  end
end
