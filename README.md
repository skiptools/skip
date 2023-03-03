# skip

The `skip` plug-in for Swift Package Manager (SPM) 5.7+ transpiles Swift into Koltin.

## Quick Start

Navigate to a folder containing an SPM project with a `Package.swift`,
or create a new one by opening `Terminal.app` and running:

```shell
mkdir SomeSwiftLibrary
cd SomeSwiftLibrary
swift package init
```


Add the following line at the bottom of your `Package.swift` file:

```swift
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.0.36")]
```

Then run:

```shell
alias skip="swift package --disable-sandbox --allow-writing-to-package-directory skip"
skip -version
```

The `skip` alias can be persisted for future `Terminal.app` shell sessions by running:

```shell
echo 'alias skip="swift package --disable-sandbox --allow-writing-to-package-directory skip"' >> ~/.zprofile
```


## Prerequisites

### System requirements

macOS 13+ (ARM or Intel).

### Xcode.app

Download and install Xcode from [https://developer.apple.com/xcode/](https://developer.apple.com/xcode/).

### Android Studio.app

Either:

1. Users of [homebrew](https://brew.sh) can run `brew install android-studio`
2. Download and install directly from [https://developer.android.com/studio/](https://developer.android.com/studio/)

## Transpiling

```shell
skip transpile
```

## Running Tests

```shell
skip test
```
