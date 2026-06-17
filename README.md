# libdatadog Ruby gem

[libdatadog](https://github.com/DataDog/libdatadog) provides a shared library containing common code used in the implementation of Datadog's libraries,
including [Continuous Profilers](https://docs.datadoghq.com/tracing/profiler/).

**NOTE**: If you're building a new Datadog library/profiler or want to contribute to Datadog's existing tools, you've come to the
right place!
Otherwise, this is possibly not the droid you were looking for.

## Development

Run `bundle exec rake` to run the tests and the style autofixer.
You can also run `bundle exec pry` for an interactive prompt that will allow you to experiment.

### Testing packaging locally

First build the libdatadog binaries for your platform from source with
`bundle exec rake libdatadog:build`, then package them into gems (without
publishing) with `bundle exec rake gem:package`.

You can check the file permissions of the built gems with
`bundle exec rake gem:validate`.

## Releasing a new version to rubygems.org

Note: No Ruby needed to run this! It all runs in CI!

1. [ ] Locate the new libdatadog release on GitHub: <https://github.com/datadog/libdatadog/releases>
2. [ ] In the <lib/libdatadog/version.rb> file:
    - [ ] Update `LIB_VERSION` with the new version. Example: Setting "25.0.0" results in the first part of the string "25.0.0.1.0.x"
    - [ ] (OPTIONAL) Update `GEM_PRERELEASE_VERSION` with a prerelease descriptor. This is only needed if you want to do a prerelease. Example: Setting ".beta" results in "25.0.0.1.0.beta".
3. [ ] Commit change, open PR, get it merged
4. [ ] Trigger the "Build" workflow on `main` with the "Push gems to RubyGems.org" option enabled: <https://github.com/DataDog/libdatadog-rb/actions/workflows/build.yml>
5. [ ] Verify that release shows up correctly on: <https://rubygems.org/gems/libdatadog>

## Contributing

See <CONTRIBUTING.md>.
