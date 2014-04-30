module Fluent
  class ElapsedTimeOutput < MultiOutput
    Plugin.register_output('elapsed_time', self)

    # To support log_level option implemented by Fluentd v0.10.43
    unless method_defined?(:log)
      define_method("log") { $log }
    end

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
        log.debug "adding store type=#{type.dump}"

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

      @tag_proc = tag_proc

      @emit_proc =
        if @each == :message
          self.method(:emit_message)
        else
          self.method(:emit_es)
        end
    end

    def emit(tag, es, chain)
      @emit_proc.call(tag, es)
      chain.next
    end

    def emit_message(tag, es)
      chain = NullOutputChain.instance
      start = Time.now
      es.each do |time, record|
        @outputs.each {|output| output.emit(tag, OneEventStream.new(time, record), chain) }
        finish = Time.now
        emit_tag = @tag_proc.call(tag)
        elapsed(emit_tag) << (finish - start).to_f
        start = finish
      end
    end

    def emit_es(tag, es)
      chain = NullOutputChain.instance
      t = Time.now
      @outputs.each {|output| output.emit(tag, es, chain) }
      emit_tag = @tag_proc.call(tag)
      elapsed(emit_tag) << (Time.now - t).to_f
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

    private

    def tag_proc
      tag_slice_proc =
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

      rstrip = Proc.new {|str, substr| str.chomp(substr) }
      lstrip = Proc.new {|str, substr| str.start_with?(substr) ? str[substr.size..-1] : str }
      tag_prefix = "#{rstrip.call(@add_tag_prefix, '.')}." if @add_tag_prefix
      tag_suffix = ".#{lstrip.call(@add_tag_suffix, '.')}" if @add_tag_suffix
      tag_prefix_match = "#{rstrip.call(@remove_tag_prefix, '.')}." if @remove_tag_prefix
      tag_suffix_match = ".#{lstrip.call(@remove_tag_suffix, '.')}" if @remove_tag_suffix
      tag_fixed = @tag if @tag
      if tag_prefix_match and tag_suffix_match
        Proc.new {|tag| "#{tag_prefix}#{rstrip.call(lstrip.call(tag_slice_proc.call(tag), tag_prefix_match), tag_suffix_match)}#{tag_suffix}" }
      elsif tag_prefix_match
        Proc.new {|tag| "#{tag_prefix}#{lstrip.call(tag_slice_proc.call(tag), tag_prefix_match)}#{tag_suffix}" }
      elsif tag_suffix_match
        Proc.new {|tag| "#{tag_prefix}#{rstrip.call(tag_slice_proc.call(tag), tag_suffix_match)}#{tag_suffix}" }
      elsif tag_prefix || @remove_tag_slice || tag_suffix
        Proc.new {|tag| "#{tag_prefix}#{tag_slice_proc.call(tag)}#{tag_suffix}" }
      else
        Proc.new {|tag| tag_fixed }
      end
    end
  end
end
