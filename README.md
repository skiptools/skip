# Skip

The `skip` plug-in for Xcode transpiles Swift targets into Kotlin projects.

## Quick Start

Add the following line at the bottom of your `Package.swift` file:

```swift
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.3.10")]
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.3.10")]
```

The comment-click your target in the Xcode project navigator
and select "Hello Skip" from the context menu.

This will create a "Skip/README.md" folder in your project root
with the steps needed to add Skip to your project.



