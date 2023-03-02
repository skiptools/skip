# skip

## Installing

Add the following line to your `Package.swift` file:

```swift
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.0.30")]
```

Then run:

```shell
swift package --disable-sandbox --allow-writing-to-package-directory skip
```
