# fluent-plugin-elapsed-time

[![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-elapsed-time.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-elapsed-time)

Fluentd plugin to measure elapsed time to process messages

## Installation

Use RubyGems:

    gem install fluent-plugin-elapsed-time

## Configuration

Example:

Following example measures the max and average time taken to process [fluent-plugin-grep](https://github.com/sonots/fluent-plugin-grep) => [fluent-plugin-parser](https://github.com/tagomoris/fluent-plugin-parser) => out_stdout chain in messages. Please notice that this plugin measures the total processing time until match chain finishes.

```apache
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

<match greped.**>
  type parse
  format ltsv
  key_name message
  remove_prefix greped
  add_prefix parsed
</match>

<match parsed.**>
  type stdout
</match>

<match elapsed>
  type stdout
</match>
```

Output will be like

```
elapsed: {"max":1.011,"avg":0.002","num":10}
```

where `max` and `avg` are the maximum and average elapsed times, and `num` is the number of messages.

## Option Parameters

* tag

    The output tag name. Default is `elapsed`

* interval

    The time interval to emit measurement results

* each

    Measure time for each `message` or `es` (event stream). Please notice that the event stream (would be a msgpack) will be unpacked if `message` is specified, which would cause performance degradation. Default is `es`.

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
