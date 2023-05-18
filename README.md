# Skip: the Swift to Kotlin transpiler

The Skip plugin for Xcode transpiles Swift libraries and test targets into Kotlin Gradle projects.

When combined with the `skiphub` ecosystem of libraries, Skip provides a framework for
creating dual-platform iOS+Android libraries and applications.

## Quick Start

1. Create a new Swift package from Xcode.app 14.3+ with `File` / `New` / `Package`.
    <details><summary>Creating a new Dual-Platform Swift Package</summary><img src="https://user-images.githubusercontent.com/659086/230632488-8bf87042-59ba-48aa-9108-71efdea5d9bb.png"></details>
    This example names the package “MyLibrary” and saves it to the Desktop.

1. Select the new `Package.swift` file in Xcode and add the following lines to activate the Skip transpiler plugin:
    ```swift
    package.dependencies += [.package(url: "https://github.com/skiptools/skip", from: "0.4.40")]
    package.dependencies += [.package(url: "https://github.com/skiptools/skiphub", from: "0.2.27")]
    ```
    <details><summary>Adding the Skip plugin to Xcode</summary><img src="https://user-images.githubusercontent.com/659086/230633291-e14e5687-a88d-4bc9-abbd-b78e9fa73c61.png"></details>
    After saving the file Xcode will download and install the Skip plugin and dependencies so they appear in the project navigator.


1. Bring up the package's context menu in the Xcode Project Navigator and select "Hello Skip" from the "skip" section of the menu.
    <details open><summary>Initializing the package with Hello Skip</summary><img src="https://user-images.githubusercontent.com/659086/230634103-37894206-f417-4a01-a149-ddab5dcb0780.png"></details>
    (alternatively, from the terminal your can run the command `swift package skip-init` from the project directory.)

1. A dialog with the package and individual targets will appear.
    <details><summary>Skip Target Selection Dialog</summary><img src="https://user-images.githubusercontent.com/659086/230633675-27ff1c95-eab5-4139-b22c-01abc2b5a7ea.png"></details>
    Leave the default package item selected to transpile all the valid targets.

1. An overview of the plugin will be shown describing the actions that will be taken and prompting for permission to save files to the project directory.
    <details><summary>The Skip Overview Dialog</summary><img src="https://user-images.githubusercontent.com/659086/230633804-3dd8504e-38c7-45e0-9c67-0edc60586064.png"></details>
    Select the “Allow Command to Change Files” button to proceed.

1. Once the plugin has completed, new targets will be appended to the end of the `Package.swift` file.
You can run the test cases by selecting `MyLibrary-Package` running on `My Mac`.
Successful transpilation and test case runs will show up in the log.
    <details><summary>Running the transpiled Kotlin test cases</summary><img src="https://user-images.githubusercontent.com/659086/229834667-f2939738-d21a-4814-94a1-63e316ca2dc5.png"></details>
    Note: the Kotlin test case must be run against the macOS platform (rather than iOS) and Gradle 8+ must be installed on the machine using the homebrew (https://brew.sh) command: `brew install gradle`

1. Test failures will be reported for both the failed Swift test cases, as well as the transpiled Kotlin JUnit tests.
For example, if we change the assertion from "*Hello* World" to "*Goodbye* World", the two failed Swift XCTest and Kotlin JUnit tests can each be seen.
    <details><summary>Browing the Swift XCTest failure report</summary><img src="https://user-images.githubusercontent.com/659086/229835265-54970fce-70f4-45fc-ba8a-899c59559486.png"></details>
    <details><summary>Browing the Kotlin JUnit failure report</summary><img src="https://user-images.githubusercontent.com/659086/229835288-9c78eff2-cef1-4eb9-bf77-6f908a2281d0.png"></details>
