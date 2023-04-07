The `skip` plugin for Xcode transpiles Swift packages into Kotlin projects.

## Quick Start

1. Create a new Swift package from Xcode.app 14.3+ with `File -> New -> Package`,
and name it "MyLibrary".
    <details><summary>Creating a new Multiplatform Swift Package</summary><img width="1512" alt="skip-onboard-01" src="https://user-images.githubusercontent.com/659086/230632488-8bf87042-59ba-48aa-9108-71efdea5d9bb.png"></details>


1. Select the `Package.swift` file and append the following lines to activate the Skip transpiler plugin:
    ```swift
    package.dependencies += [.package(url: "https://github.com/skiptools/skip", from: "0.3.16")]
    package.dependencies += [.package(url: "https://github.com/skiptools/skiphub", from: "0.1.2")]
    ```
    After saving the file, Xcode will download and install the Skip packages so they appear in the project navigator.
    <details><summary>Adding the Skip plugin to Xcode</summary><img width="1578" alt="skip-onboard-01" src="https://user-images.githubusercontent.com/659086/230633291-e14e5687-a88d-4bc9-abbd-b78e9fa73c61.png"></details>
    

1. Select your package's root folder in the Xcode Project Navigator
and select "Hello Skip" from the "skip" section of the package's
context menu.
Alternatively, from the terminal your can run the command 
`swift package plugin skip-init` from the project directory. 
    <details><summary>Initializing the package with Hello Skip</summary><img width="1512" alt="skip-onboard-02" src="https://user-images.githubusercontent.com/659086/230634103-37894206-f417-4a01-a149-ddab5dcb0780.png"></details>


1. When prompted to select the targets, you can choose which individual
targets should have transpilation peer targets created for them.
Leaving the default item selected will add all the valid targets.
    <details><summary>Skip Target Selection Dialog</summary><img width="1512" alt="skip-onboard-03" src="https://user-images.githubusercontent.com/659086/230633675-27ff1c95-eab5-4139-b22c-01abc2b5a7ea.png"></details>

1. An overview of the plugin will be shown describing the actions that will be taken and prompting for permission to save files to the project directory.
    <details><summary>The Skip Overview Dialog</summary><img width="1578" alt="skip-onboard-04" src="https://user-images.githubusercontent.com/659086/230633804-3dd8504e-38c7-45e0-9c67-0edc60586064.png"></details>

1. Once the plugin has completed, new targets will be appended to the end of the `Package.swift` file.
You can run the test cases by selecting `MyLibrary-Package` running on `My Mac`.
Successful transpilation and test case runs will show up in the log.
Note that the Kotlin test cases must be run against the macOS target,
and Gradle must be installed on the machine (e.g. with: `brew install gradle`
or from https://gradle.org).
    <details><summary>Running the transpiled Kotlin test cases</summary><img width="1412" alt="skip-init-screenshot-2" src="https://user-images.githubusercontent.com/659086/229834667-f2939738-d21a-4814-94a1-63e316ca2dc5.png"></details>

1. Test failures will be reported for both the failed Swift test cases,
as well as the transpiled Kotlin JUnit tests.
For example, if we change the assertion from "*Hello* World" to "*Goodbye* World",
the two failed Swift XCTest and Kotlin JUnit tests can each be seen.
    <details><summary>Browing the Swift XCTest failure report</summary><img width="1412" alt="skip-init-screenshot-3" src="https://user-images.githubusercontent.com/659086/229835265-54970fce-70f4-45fc-ba8a-899c59559486.png"></details>
    <details><summary>Browing the Kotlin JUnit failure report</summary><img width="1412" alt="skip-init-screenshot-4" src="https://user-images.githubusercontent.com/659086/229835288-9c78eff2-cef1-4eb9-bf77-6f908a2281d0.png"></details>
