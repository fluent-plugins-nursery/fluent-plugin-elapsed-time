# fluent-plugin-performance

[![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-performance.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-performance)

Fluentd plugin to measure performance to process messages

## Installation

Use RubyGems:

    gem install fluent-plugin-performance

## Configuration

Example:

```apache
<match **>
  type performance
  tag performance
  interval 60
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

<match perforamnce>
  type stdout
</match>
```

Notice that this examples measures the total time taken to process [fluent-plugin-grep](https://github.com/sonots/fluent-puglin-grep) **and** [fluent-plugin-parser](https://github.com/tagomoris/fluent-plugin-parser), **and** out_stdout.

## Option Parameters

* tag

    The output tag name

* interval

    The time interval to emit measurement results

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
