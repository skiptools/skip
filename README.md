# Skip

[Skip](https://skip.tools) is a technology for creating dual-platform mobile apps in Swift and SwiftUI. This repository houses the `skip` tool for creating, managing, testing, and packaging Skip projects.

## Installation

See the Skip product's [Getting Started](https://skip.tools/docs/#getting-started) documentation for system requirements and installation instructions.

## Guide

Once installed, the `skip` tool is self-documenting. Use the `help` command to see a full list of other available commands:

```shell
% skip help
```

You can also get help on a particular command. For example, to see details and available options for the `skip doctor` command:

```shell
% skip help doctor
```

See the Skip product [documentation](https://skip.tools/docs) for common use cases, including how to use `skip` to [start a Skip app](https://skip.tools/docs/#start-new-app) and [start a dual-platform Skip library](http://skip.tools/docs/#start-new-library).

## Known Issues

This section lists known issues with the `skip` tool and associated Xcode plugins.

- Xcode sometimes reports error messages like the following:

    ```shell
    Internal inconsistency error (didStartTask): targetID (174) not found in _activeTargets.
    Internal inconsistency error (didEndTask): '12' missing from _activeTasks.
    ```

    When these errors occur, the build may appear to complete successfully although changes are not applied. Unfortunately, this appears to be an Xcode bug. We have found the following workarounds:

    - Continue to retry the build. Eventually Xcode will complete successfully, although the errors may continue to become more frequest until you are foced to apply one of the other solutions below.
    - Restart Xcode.
    - Clean and rebuild.

    You can read more about this Xcode error on the [Swift.org forums](https://forums.swift.org/t/internal-inconsistency-error-didstarttask/61194/2).
