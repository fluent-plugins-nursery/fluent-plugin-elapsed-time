module Fluent
  class MeasureTimeOutput < MultiOutput
    Plugin.register_output('measure_time', self)

    config_param :tag, :string, :default => 'measure_time'
    config_param :interval, :time, :default => 60
    config_param :each, :default => :es do |val|
      case val.downcase
      when 'es'
        :es
      when 'message'
        :message
      else
        raise ConfigError, "out_measure_time: each should be 'es' or 'message'"
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

      @emit_proc =
        if @each == :message
          chain = NullOutputChain.instance
          Proc.new {|tag, es|
            start = Time.now
            es.each do |time, record|
              @outputs.each {|output| output.emit(tag, OneEventStream.new(time, record), chain) }
              finish = Time.now
              @elapsed << (finish - start).to_f
              start = finish
            end
          }
        else
          chain = NullOutputChain.instance
          Proc.new {|tag, es|
            t = Time.now
            @outputs.each {|output| output.emit(tag, es, chain) }
            @elapsed << (Time.now - t).to_f
          }
        end
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
        avg = elapsed.map(&:to_f).inject(:+) / num.to_f
        Engine.emit(@tag, Engine.now, {"max" => max, "avg" => avg, "num" => num})
      end
    end

    def emit(tag, es, chain)
      @emit_proc.call(tag, es)
      chain.next
    end
  end
end
