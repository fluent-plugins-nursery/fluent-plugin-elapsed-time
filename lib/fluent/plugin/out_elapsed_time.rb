module Fluent
  class ElapsedTimeOutput < MultiOutput
    Plugin.register_output('elapsed_time', self)

    config_param :tag, :string, :default => 'elapsed'
    config_param :add_tag_prefix, :string, :default => nil
    config_param :remove_tag_prefix, :string, :default => nil
    config_param :aggregate, :string, :default => 'all'
    config_param :interval, :time, :default => 60
    config_param :each, :default => :es do |val|
      case val.downcase
      when 'es'
        :es
      when 'message'
        :message
      else
        raise ConfigError, "out_elapsed_time: each should be 'es' or 'message'"
      end
    end 

    def initialize
      super
      @outputs = []
      @elapsed = {}
    end

    # for test
    attr_reader :outputs

    def elapsed(tag = :all)
      @elapsed[tag] ||= []
    end

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

      case @aggregate
      when 'all'
        raise ConfigError, "out_elapsed_time: `tag` must be specified with aggregate all" if @tag.nil?
      when 'tag'
        raise ConfigError, "out_elapsed_time: `add_tag_prefix` or `remove_tag_prefix` must be specified with aggregate tag" if @add_tag_prefix.nil? and @remove_tag_prefix.nil?
      else
        raise ConfigError, "out_elapsed_time: aggregate allows `tag` or `all`"
      end

      @tag_prefix = "#{@add_tag_prefix}." if @add_tag_prefix
      @tag_prefix_match = "#{@remove_tag_prefix}." if @remove_tag_prefix
      @tag_proc =
        if @tag_prefix and @tag_prefix_match
          Proc.new {|tag| "#{@tag_prefix}#{lstrip(tag, @tag_prefix_match)}" }
        elsif @tag_prefix_match
          Proc.new {|tag| lstrip(tag, @tag_prefix_match) }
        elsif @tag_prefix
          Proc.new {|tag| "#{@tag_prefix}#{tag}" }
        elsif @tag
          Proc.new {|tag| @tag }
        else
          Proc.new {|tag| tag }
        end

      @push_elapsed_proc =
        case @aggregate
        when 'all'
          Proc.new {|tag, elapsed_time| elapsed(:all) << elapsed_time }
        when 'tag'
          Proc.new {|tag, elapsed_time| elapsed(tag) << elapsed_time }
        end

      @emit_proc =
        if @each == :message
          chain = NullOutputChain.instance
          Proc.new {|tag, es|
            start = Time.now
            es.each do |time, record|
              @outputs.each {|output| output.emit(tag, OneEventStream.new(time, record), chain) }
              finish = Time.now
              elapsed = (finish - start).to_f
              @push_elapsed_proc.call(tag, elapsed)
              start = finish
            end
          }
        else
          chain = NullOutputChain.instance
          Proc.new {|tag, es|
            t = Time.now
            @outputs.each {|output| output.emit(tag, es, chain) }
            elapsed = (Time.now - t).to_f
            @push_elapsed_proc.call(tag, elapsed)
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
      elapseds, @elapsed = @elapsed, {}
      elapseds.each do |tag, elapsed|
        unless elapsed.empty?
          max = elapsed.max
          num = elapsed.size
          avg = elapsed.map(&:to_f).inject(:+) / num.to_f
          emit_tag = @tag_proc.call(tag)
          Engine.emit(emit_tag, Engine.now, {"max" => max, "avg" => avg, "num" => num})
        end
      end
    end

    def emit(tag, es, chain)
      @emit_proc.call(tag, es)
      chain.next
    end

    def lstrip(string, substring)
      string.index(substring) == 0 ? string[substring.size..-1] : string
    end
  end
end
