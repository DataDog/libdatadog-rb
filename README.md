# libdatadog Ruby gem

`libdatadog` provides a shared library containing common code used in the implementation of Datadog's libraries,
including [Continuous Profilers](https://docs.datadoghq.com/tracing/profiler/).

**NOTE**: If you're building a new Datadog library/profiler or want to contribute to Datadog's existing tools, you've come to the
right place!
Otherwise, this is possibly not the droid you were looking for.

## Development

Run `bundle exec rake` to run the tests and the style autofixer.
You can also run `bundle exec pry` for an interactive prompt that will allow you to experiment.

### Building libdatadog from source

The `build_ffi` task compiles libdatadog locally using the builder crate. This requires a Rust toolchain.
The required Rust version matches the one used by libdatadog itself (currently **1.84.1**).

Install [rustup](https://rustup.rs) if you don't have it already:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Then install and activate the required version:

```sh
rustup install 1.84.1
rustup default 1.84.1
```

Once Rust is set up, run the build:

```sh
bundle exec rake build_ffi
```

This places the compiled artifacts for the current platform under `build/libdatadog-<version>/<platform>/`.

> **Note:** Rust is only needed for `build_ffi`. All other tasks — including `fetch_release_artifacts`,
> `package_from_github`, and the default test suite — work without a Rust installation.

### Testing packaging locally

You can use `bundle exec rake package_from_github` to download the pre-built release artifacts and package
the gem locally without publishing it.

TIP: If the test that checks for permissions ("gem release process ... sets the right permissions on the gem files"), fails you
may need to run `umask 0022 && bundle exec rake package_from_github` so that the generated packages have the correct permissions.

## Releasing a new version to rubygems.org

Note: No Ruby needed to run this! It all runs in CI!

1. [ ] Locate the new libdatadog release on GitHub: <https://github.com/datadog/libdatadog/releases>
2. [ ] In the <lib/libdatadog/version.rb> file:
    - [ ] Update `LIB_VERSION` with the new version. Example: Setting "25.0.0" results in the first part of the string "25.0.0.1.0.x"
    - [ ] (OPTIONAL) Update `GEM_PRERELEASE_VERSION` with a prerelease descriptor. This is only needed if you want to do a prerelease. Example: Setting ".beta" results in "25.0.0.1.0.beta".
3. [ ] Commit change, open PR, get it merged
4. [ ] Trigger the "Publish" workflow in <https://github.com/DataDog/libdatadog-rb/actions/workflows/publish.yml>
5. [ ] Verify that release shows up correctly on: <https://rubygems.org/gems/libdatadog>

## Contributing

See <CONTRIBUTING.md>.
