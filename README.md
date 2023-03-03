# skip

## Installing

Add the following line at the bottom of your `Package.swift` file:

```swift
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.0.33")]
```

Then run:

```shell
swift package --disable-sandbox --allow-writing-to-package-directory skip
```
