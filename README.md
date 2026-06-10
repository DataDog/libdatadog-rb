# libdatadog Ruby gem

[libdatadog](https://github.com/DataDog/libdatadog) provides a shared library containing common code used in the implementation of Datadog's libraries,
including [Continuous Profilers](https://docs.datadoghq.com/tracing/profiler/).

**NOTE**: If you're building a new Datadog library/profiler or want to contribute to Datadog's existing tools, you've come to the
right place!
Otherwise, this is possibly not the droid you were looking for.

## Development

Run `bundle exec rake` to run the tests and the style autofixer.
You can also run `bundle exec pry` for an interactive prompt that will allow you to experiment.

### Building from source

`bundle exec rake libdatadog:build` builds libdatadog from source for the current platform
using libdatadog's own [`builder` crate](https://github.com/DataDog/libdatadog/tree/main/builder).
It requires a Rust toolchain (plus `cmake` and autotools); the Nix dev shell provides all of these.
The default build writes artifacts to `vendor/libdatadog-<LIB_VERSION>/<platform>/` (the
location the gem is packaged from); explicit-ref builds (see below) write to a directory named
after the ref instead, so they are not mislabeled as the pinned release.

By default it builds the pinned `v<LIB_VERSION>` tag. Set the optional `LIBDATADOG_REF`
environment variable to build something else. Its value is always an explicit
`<kind>:<value>` pair, where `kind` is one of:

- `tag` — a git tag, e.g. `LIBDATADOG_REF=tag:v33.0.0`.
- `branch` — a git branch, e.g. `LIBDATADOG_REF=branch:my-feature`.
- `commit` — a git commit, e.g. `LIBDATADOG_REF=commit:<sha>`.
- `path` — a local libdatadog checkout, e.g. `LIBDATADOG_REF=path:/path/to/libdatadog`.

The kind is always stated explicitly (no guessing), so a value without a recognized prefix
fails fast. When `LIBDATADOG_REF` is unset, the pinned `v<LIB_VERSION>` tag is built.

Independently of the above, `LIBDATADOG_FEATURES` sets a comma-separated cargo feature
override and applies to any build.

Git builds (tag/branch/commit) pass `cargo install --locked`, so they reproducibly use the
dependency versions pinned in libdatadog's `Cargo.lock`. Local-path builds omit `--locked`,
since the checkout may be modified.

```sh
LIBDATADOG_REF=commit:<sha> bundle exec rake libdatadog:build
```

### Testing packaging locally

You can use `bundle exec rake package` to generate packages locally without publishing them.

TIP: If the test that checks for permissions ("gem release process ... sets the right permissions on the gem files"), fails you
may need to run `umask 0022 && bundle exec rake package` so that the generated packages have the correct permissions.

## Releasing a new version to rubygems.org

Note: No Ruby needed to run this! It all runs in CI!

1. [ ] Locate the new libdatadog release on GitHub: <https://github.com/datadog/libdatadog/releases>
2. [ ] Update the `LIB_GITHUB_RELEASES` section of the `Rakefile` with the hashes from the new version
3. [ ] In the <lib/libdatadog/version.rb> file:
    - [ ] Update `LIB_VERSION` with the new version. Example: Setting "25.0.0" results in the first part of the string "25.0.0.1.0.x"
    - [ ] (OPTIONAL) Update `GEM_PRERELEASE_VERSION` with a prerelease descriptor. This is only needed if you want to do a prerelease. Example: Setting ".beta" results in "25.0.0.1.0.beta".
4. [ ] Commit change, open PR, get it merged
5. [ ] Trigger the "Publish" workflow in <https://github.com/DataDog/libdatadog-rb/actions/workflows/publish.yml>
6. [ ] Verify that release shows up correctly on: <https://rubygems.org/gems/libdatadog>

## Contributing

See <CONTRIBUTING.md>.
