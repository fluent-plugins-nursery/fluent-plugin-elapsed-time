# fluent-plugin-elapsed-time

[![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-elapsed-time.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-elapsed-time)

Fluentd plugin to measure elapsed time to process messages

## Installation

Use RubyGems:

    gem install fluent-plugin-elapsed-time

## Illustration

This illustration draws how fluent-plugin-elapsed-time measures elapsed times.

```
     +–––––––––––––+    +––––––––––––––+   +––––––––––––––+   +–––––––––––––––+
     |   Input     |    |  ElapsedTime |   |   Output     |   |   Output      |
     +––––––+––––––+    +––––––+–––––––+   +––––––+–––––––+   +–––––––+–––––––+
#on_message |                  |                  |                   |
            +––––––––––––––––––>                  |                   |
            |      #emit       | start = Time.now |                   |
            |                  +––––––––––––––––––>                   |
            |                  |      #emit       +–––––––––––––––––––>        
            |                  |                  |     #emit         |        
            |                  |                  <– – – – –  – – – – +        
            |                  <– – – – – – – – – +                   |
            |                  | elapsed = Time.now - start           |
            <– – – – – - – – – +                  |                   |
            |                  |                  |                   |
            +                  +                  +                   +
```

## Configuration

Example:

Following example measures the max and average time taken to process [fluent-plugin-grep](https://github.com/sonots/fluent-plugin-grep) => out_stdout chain in messages. Please notice that this plugin measures the total processing time until match chain finishes.

```apache
<match greped.**>
  type stdout
</match>

<match elapsed>
  type stdout
</match>

<match **>
  type elapsed_time
  tag elapsed
  interval 60
  each message
  <store>
    type grep
    exclude foobar
    add_tag_prefix greped
  </store>
</match>
```

Output will be like

```
elapsed: {"max":1.011,"avg":0.002","num":10}
```

where `max` and `avg` are the maximum and average elapsed times, and `num` is the number of messages.

## Option Parameters

* interval

    The time interval to emit measurement results

* each

    Measure time for each `message` or `es` (event stream). Please notice that the event stream (would be a msgpack) will be unpacked if `message` is specified, which would cause performance degradation. Default is `es`.

* tag

    The output tag name. Default is `elapsed`

* add_tag_prefix

    Add tag prefix for output message

* remove_tag_prefix

    Remove tag prefix for output message

* remove_tag_slice *min..max*

    Remove tag parts by slice function. FYI: This option behaves like `tag.split('.').slice(min..max)`.

    For example,

        remove_tag_slice 0..-2

    changes an input tag `foo.bar.host1` to `foo.bar`. 

* aggregate

    Measure and emit outputs for each `tag` or `all`. Default is `all`.

    `all` measures `max` and `avg` for all input messages.
    `tag` measures `max` and `avg` for each tag *modified* by `add_tag_prefix`, `remove_tag_prefix`, or `remove_tag_slice`. 

* zero_emit *bool*

    Emit 0 on the next interval. This is useful for some software which requires resetting data such as [GrowthForecast](http://kazeburo.github.io/GrowthForecast).

        elapsed: {"max":1.013,"avg":0.123,"num"=>0}
        # after @interval later
        elapsed: {"max":0,"avg":0,"num"=>0}

## Relatives

* [fluent-plugin-measure_time](https://github.com/sonots/fluent-plugin-measure_time)

  * This plugin make possible to measure the elapsed time of not only output plugins but also input plugins.
  * Also, this plugin has a flexibility to measure arbitrary methods of plugins. 
  * But, this does not have flexibility of output messages such as `add_tag_prefix`, `aggregate` options because of its limitaion of internal mechanism.

## ChangeLog

See [CHANGELOG.md](CHANGELOG.md) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new [Pull Request](../../pull/new/master)

## Copyright

Copyright (c) 2014 Naotoshi Seo. See [LICENSE](LICENSE) for details.
