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
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.1.7")]
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

## System Requirements

macOS 13+ (ARM or Intel), [XCode.app](https://developer.apple.com/xcode/) and [Android Studio.app](https://developer.android.com/studio/).



