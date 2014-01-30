module Fluent
  class ElapsedTimeOutput < MultiOutput
    Plugin.register_output('elapsed_time', self)

    config_param :tag, :string, :default => 'elapsed'
    config_param :add_tag_prefix, :string, :default => nil
    config_param :remove_tag_prefix, :string, :default => nil
    config_param :remove_tag_slice, :string, :default => nil
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
    config_param :zero_emit, :bool, :default => false

    def initialize
      super
      @outputs = []
      @elapsed = {}
    end

    # for test
    attr_reader :outputs

    def elapsed(tag = "elapsed") # default: @tag
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

      @tag_slice_proc =
        if @remove_tag_slice
          lindex, rindex = @remove_tag_slice.split('..', 2)
          if lindex.nil? or rindex.nil? or lindex !~ /^-?\d+$/ or rindex !~ /^-?\d+$/
            raise Fluent::ConfigError, "out_elapsed_time: remove_tag_slice must be formatted like [num]..[num]"
          end
          l, r = lindex.to_i, rindex.to_i
          Proc.new {|tag| (tags = tag.split('.')[l..r]).nil? ? "" : tags.join('.') }
        else
          Proc.new {|tag| tag }
        end

      @tag_prefix = "#{@add_tag_prefix}." if @add_tag_prefix
      @tag_prefix_match = "#{@remove_tag_prefix}." if @remove_tag_prefix
      @tag_proc =
        if @tag_prefix and @tag_prefix_match
          Proc.new {|tag| "#{@tag_prefix}#{lstrip(@tag_slice_proc.call(tag), @tag_prefix_match)}" }
        elsif @tag_prefix_match
          Proc.new {|tag| lstrip(@tag_slice_proc.call(tag), @tag_prefix_match) }
        elsif @tag_prefix
          Proc.new {|tag| "#{@tag_prefix}#{@tag_slice_proc.call(tag)}" }
        elsif @tag
          Proc.new {|tag| @tag }
        else
          Proc.new {|tag| @tag_slice_proc.call(tag) }
        end

      @emit_proc =
        if @each == :message
          chain = NullOutputChain.instance
          Proc.new {|tag, es|
            start = Time.now
            es.each do |time, record|
              @outputs.each {|output| output.emit(tag, OneEventStream.new(time, record), chain) }
              finish = Time.now
              emit_tag = @tag_proc.call(tag)
              elapsed(emit_tag) << (finish - start).to_f
              start = finish
            end
          }
        else
          chain = NullOutputChain.instance
          Proc.new {|tag, es|
            t = Time.now
            @outputs.each {|output| output.emit(tag, es, chain) }
            emit_tag = @tag_proc.call(tag)
            elapsed(emit_tag) << (Time.now - t).to_f
          }
        end
    end

    def initial_elapsed(prev_elapsed = nil)
      return {} if !@zero_emit or prev_elapsed.nil?
      elapsed = {}
      prev_elapsed.keys.each do |tag|
        next if prev_elapsed[tag].empty? # Prohibit to emit anymore
        elapsed[tag] = []
      end
      elapsed
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
      flushed_elapsed, @elapsed = @elapsed, initial_elapsed(@elapsed)
      messages = {}
      flushed_elapsed.each do |tag, elapsed|
        num = elapsed.size
        max = num == 0 ? 0 : elapsed.max
        avg = num == 0 ? 0 : elapsed.map(&:to_f).inject(:+) / num.to_f
        messages[tag] = {"max" => max, "avg" => avg, "num" => num}
      end
      messages.each {|tag, message| Engine.emit(tag, Engine.now, message) }
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
