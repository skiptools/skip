# Skip

[![CI](https://github.com/skiptools/skip/actions/workflows/ci.yml/badge.svg)](https://github.com/skiptools/skip/actions/workflows/ci.yml)
[![Slack](https://img.shields.io/badge/slack-chat-informational.svg?label=Slack&logo=slack)](https://www.skip.dev/slack)

Skip is a technology for creating dual-platform apps in Swift that run on iOS and Android.
Read the [documentation](https://skip.dev/docs/) to learn more about Skip.

This repository hosts the Skip Xcode and SwiftPM build plugin[^plugins]. It works works hand-in-hand with the [skipstone](https://github.com/skiptools/skipstone) tool, which is the binary distribution that powers both the `skip` CLI and the plugin commands. Most of the interesting code is in `skipstone`, but this is the package which Skip projects will directly depend on. For more information on how Skip packages are architected, see the [Framework Structure docs](https://skip.dev/docs/project-types/#framework_structure), or see one of the sample projects like [Hello Skip](https://github.com/skiptools/skipapp-hello).

[^plugins]: Extend package manager functionality with build or command plugins. — [https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/plugins/](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/plugins/)

For those who want to dive _right_ in without delay, the [Getting Started Guide](https://skip.dev/docs/gettingstarted/) can be summarized like so:

```console
brew install skiptools/skip/skip
skip checkup
skip create
```

…and your Skip project will be created and opened in Xcode.

This repository also hosts the Skip forums for [support and discussions](http://community.skip.dev) as well as specific [issues and bug reports](https://github.com/skiptools/skip/issues).


