The `skip` plug-in for Xcode transpiles Swift targets into Kotlin projects.

## Quick Start

To add the Skip transpiler plugin and core library support to a Swift library
project, add the following lines at the end of the `Package.swift` file:

```
package.dependencies += [.package(url: "https://github.com/skiptools/skip", from: "0.3.0")]
package.dependencies += [.package(url: "https://github.com/skiptools/skiphub", from: "0.1.0")]
```

Select your package's root folder in the Xcode Project Navigator
and select "Hello Skip" from the "skip" section of the package's
context menu.
Alternatively, from the terminal your can run the command 
`swift package plugin skip-init` from the project directory. 

When prompted to select the targets, you can choose which individual
targets should have transpilation peer targets created for them.
You will then be prompted with an overview of the plugin and
request permission to save files to the project directory.
