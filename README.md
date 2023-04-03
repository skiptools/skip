The `skip` plug-in for Xcode transpiles Swift targets into Kotlin projects.

## Quick Start

Add the following two lines at the end of your `Package.swift` file:

```
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.3.11")]
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.3.11")]
```

Command-click your package in the Xcode Project Navigator
and select "Hello Skip" from the context menu (or run the
command `swift package plugin skip-init` from the terminal
in the project directory).

