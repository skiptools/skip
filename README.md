The `skip` plug-in for Xcode transpiles Swift targets into Kotlin projects.

## Quick Start

Create a new Swift package from Xcode.app with File -> New -> Package,
and name it "MyLibrary".

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

<img width="1412" alt="skip-init-screenshot-0" src="https://user-images.githubusercontent.com/659086/229834312-3b5d3ac5-110a-48b0-946e-e502eb930409.png">

When prompted to select the targets, you can choose which individual
targets should have transpilation peer targets created for them.
Leaving the default item selected will add all the valid targets.

You will then be prompted with an overview of the plugin and
request permission to save files to the project directory.

<img width="1412" alt="skip-init-screenshot-1" src="https://user-images.githubusercontent.com/659086/229834477-795444a2-a5fd-45fe-b9bd-c066b8aa55e0.png">

Once the plugin has completed, new targets will be appended to the end of the `Package.swift` file.
You can run the test cases by selecting `MyLibrary-Package` running on `My Mac`.
Successful transpilation and test case runs will show up in the log.
Note that the Kotlin test cases must be run against the macOS target,
and Gradle must be installed on the machine (e.g. with: `brew install gradle`
or from https://gradle.org).

<img width="1412" alt="skip-init-screenshot-2" src="https://user-images.githubusercontent.com/659086/229834667-f2939738-d21a-4814-94a1-63e316ca2dc5.png">

Test failures will be reported for both the failed Swift test cases,
as well as the transpiled Kotlin JUnit tests.
For example, if we change the assertion from "*Hello* World" to "*Goodbye* World",
the two failed Swift XCTest and Kotlin JUnit tests can each be seen.

<img width="1412" alt="skip-init-screenshot-3" src="https://user-images.githubusercontent.com/659086/229835265-54970fce-70f4-45fc-ba8a-899c59559486.png">

<img width="1412" alt="skip-init-screenshot-4" src="https://user-images.githubusercontent.com/659086/229835288-9c78eff2-cef1-4eb9-bf77-6f908a2281d0.png">





