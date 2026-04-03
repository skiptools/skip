// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
import Either

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct DevicesCommand: SkipCommand, StreamingCommand, OutputOptionsCommand, ToolOptionsCommand {
    typealias Output = DevicesOutput
    
    static var configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List connected devices and emulators/simulators",
        usage: """
        # List all connected Android and iOS devices
        skip devices
        """,
        discussion: """
        Lists all connected Android emulators and devices (via adb) and iOS simulators \
        and devices (via simctl and devicectl). Useful for verifying which targets are \
        available before running or testing.
        """,
        shouldDisplay: true)

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func performCommand(with out: MessageQueue) async throws {
        try await listAndroidDevices(with: out)
        try await listIOSSimulators(with: out)
        try await listIOSDevices(with: out)
    }

    func listIOSDevices(with out: MessageQueue) async throws {
        // xcrun devicectl list devices --timeout 5 --json-output -
        // need to ignore stderror since some non-JSON debugging info is sent there
        let deviceOutput: XCDeviceOutput = try await launchTool("xcrun", arguments: ["devicectl", "list", "devices", "--timeout", "10", "--json-output", "-"], includeStdErr: false).parseJSON()
        for device in deviceOutput.result.devices {
            let info = DevicesOutput(id: device.identifier, type: .device, platform: .ios, info: .init(device))
            await out.yield(info)
        }
    }

    func listIOSSimulators(with out: MessageQueue) async throws {
        // xcrun simctl list devices booted iOS --json
        let simctlOutput: SimctlOutput = try await launchTool("xcrun", arguments: ["simctl", "list", "devices", "booted", "iOS", "--json"], includeStdErr: false).parseJSON()
        for (_, devices) in simctlOutput.devices.map({ ($0, $1) }) {
            for device in devices {
                if let id = device.udid {
                    let info = DevicesOutput(id: id, type: .emulator, platform: .ios, info: .init(device))
                    await out.yield(info)
                }
            }
        }
    }

    func listAndroidDevices(with out: MessageQueue) async throws {
        for device in try await getAndroidDevices() {
            let info = DevicesOutput(id: device.id, type: .device, platform: .android, info: .init(device.info))
            await out.yield(info)
        }
    }

    public struct DevicesCommandError : LocalizedError {
        public var errorDescription: String?
    }

    struct SimctlOutput : Codable {
        let devices: [String: [SimctlDevice]]

        struct SimctlDevice : Codable {
            let lastBootedAt: String? // "2024-01-26T14:46:09Z",
            let dataPath: String? // "/Users/XXX/Library/Developer/CoreSimulator/Devices/15D3857C-12C8-4FB8-9CB5-7D79E4CC0748/data",
            let dataPathSize: Int64? // 7656980480,
            let logPath: String? // "/Users/XXX/Library/Logs/CoreSimulator/15D3857C-12C8-4FB8-9CB5-7D79E4CC0748",
            let udid: String? // "15D3857C-12C8-4FB8-9CB5-7D79E4CC0748",
            let isAvailable: Bool? // true,
            let logPathSize: Int64? // 827392,
            let deviceTypeIdentifier: String? // "com.apple.CoreSimulator.SimDeviceType.iPhone-14",
            let state: String? // "Booted",
            let name: String? // "iPhone 14"

        }
    }

    struct DevicesOutput : MessageEncodable, Decodable {
        let id: String
        let type: DeviceType
        let platform: DevicePlatform

        //let deviceStatus: String
        let info: Either<[String: String]>.Or<XCDevice>.Or<SimctlOutput.SimctlDevice>

        /// Returns the message for the output with optional ANSI coloring
        func message(term: Term) -> String? {
            "platform: \(platform) type: \(type) id: \(id)"
        }

        enum DevicePlatform : String, Codable { case ios, android }
        enum DeviceType : String, Codable { case device, emulator }
    }

    struct XCDeviceOutput : Codable {
        /**
         ```
         "info" : {
           "arguments" : [
             "devicectl",
             "list",
             "devices",
             "--timeout",
             "10",
             "--json-output",
             "-"
           ],
           "commandType" : "devicectl.list.devices",
           "environment" : {
             "TERM" : "xterm-256color"
           },
           "jsonVersion" : 2,
           "outcome" : "success",
           "version" : "355.18"
         }
         ```
         */
        //var info: XCDeviceInfo

        var result: XCDeviceResult

        struct XCDeviceResult: Codable {
            var devices: [XCDevice]
        }
    }

    struct XCDevice : Codable {
        let identifier: String // "C85D41ED-3617-48D1-974E-30A53A3E629A"
        var visibilityClass: String? // "default"

        /// `{ "featureIdentifier" : "com.apple.coredevice.feature.unpairdevice", "name" : "Unpair Device" }`
        var capabilities: [[String: String]]?
        var connectionProperties: ConnectionProperties?
        var deviceProperties: DeviceProperties?

        struct ConnectionProperties : Codable {
            var authenticationType: String? // "manualPairing"
            var isMobileDeviceOnly: Bool? // false
            var lastConnectionDate: String? // "2024-01-26T19:47:42.165Z"
            var localHostnames: [String]?
            var pairingState: String?
            var potentialHostnames: [String]?
            var transportType: String? // "localNetwork"
            var tunnelIPAddress: String?
            var tunnelState: String? // "disconnected"
            var tunnelTransportProtocol: String? // "tcp"
        }

        struct DeviceProperties : Codable {
            var bootedFromSnapshot: Bool?
            var bootedSnapshotName: String?
            var bootState: String?
            var ddiServicesAvailable: Bool?
            var developerModeStatus: String?
            var hasInternalOSBuild: Bool?
            var name: String?
            var osBuildUpdate: String?
            var osVersionNumber: String?
            var rootFileSystemIsWritable: Bool?
            var screenViewingURL: String?
        }

        struct HardwareProperties : Codable {
            var cpuType: CPUType?
            var deviceType: String?
            var ecid: Int?
            var hardwareModel: String?
            var internalStorageCapacity: Int?
            var marketingName: String?
            var platform: String?
            var productType: String?
            var serialNumber: String?
            var supportedCPUTypes: [CPUType]?
            var supportedDeviceFamilies: [Int]?
            var thinningProductType: String?
            var udid: String?

        }

        struct CPUType : Codable {
            var name: String?
            var subType: Int?
            var cpuType: Int?
        }
    }
}

/// A connected Android device or emulator as reported by `adb devices -l`.
struct AndroidDevice {
    /// The device serial (e.g. "emulator-5554" or a USB serial)
    let id: String
    /// Key-value pairs from the device info string (product, model, device, transport_id, etc.)
    let info: [String: String]

    /// Whether this device appears to be an emulator rather than a physical device.
    /// Detected by the serial starting with "emulator-" or the "device" info field starting with "emu".
    var isEmulator: Bool {
        id.hasPrefix("emulator-") || info["device"]?.hasPrefix("emu") == true
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension ToolOptionsCommand where Self: StreamingCommand {
    /// Query `adb devices -l` and return the list of connected Android devices/emulators.
    func getAndroidDevices() async throws -> [AndroidDevice] {
        let adbDevicesPattern = try NSRegularExpression(pattern: #"^(\S+)\s+(\S+)(.*)$"#)
        var devices: [AndroidDevice] = []
        var seenDevicesHeader = false
        for try await pout in try await launchTool("adb", arguments: ["devices", "-l"]) {
            let line = pout.line
            if line.hasPrefix("List of devices") {
                seenDevicesHeader = true
            } else if seenDevicesHeader {
                guard let parts = adbDevicesPattern.extract(from: line) else {
                    continue
                }
                guard let deviceID = parts.first,
                      let _ = parts.dropFirst(1).first,
                      let deviceInfo = parts.dropFirst(2).first else {
                    continue
                }
                var deviceInfoMap = [String: String]()
                for keyValue in deviceInfo.split(separator: " ").map({ $0.split(separator: ":") }) {
                    if keyValue.count == 2 {
                        deviceInfoMap[keyValue[0].description] = keyValue[1].description
                    }
                }
                devices.append(AndroidDevice(id: deviceID, info: deviceInfoMap))
            }
        }
        return devices
    }

    /// Resolve an Android emulator/device identifier to a concrete `ANDROID_SERIAL` value.
    ///
    /// - Parameter androidSerial: The value to resolve:
    ///   - `"auto"`: honour existing `ANDROID_SERIAL` env var, otherwise auto-detect (preferring emulators).
    ///   - Any other string: treat as an explicit device serial and verify it exists.
    /// - Returns: The serial to set as `ANDROID_SERIAL`, or `nil` when adb can figure it out on its own (single device).
    func resolveAndroidSerial(androidSerial: String, with out: MessageQueue) async throws -> String? {
        if androidSerial == "auto" {
            // If the user already set ANDROID_SERIAL in the environment, honour it
            if let existing = ProcessInfo.processInfo.environment["ANDROID_SERIAL"], !existing.isEmpty {
                return existing
            }
            // Otherwise query connected devices, preferring emulators
            let devices = try await getAndroidDevices()
            if devices.isEmpty {
                throw DevicesCommand.DevicesCommandError(errorDescription: "No connected Android devices or emulators were found. Launch an emulator from Android Studio's Virtual Device Manager, or connect a device via USB.")
            }
            if devices.count == 1 {
                return nil // adb will target the only device automatically
            }
            // Multiple devices: prefer an emulator over a physical device
            let emulators = devices.filter { $0.isEmulator }
            let target = emulators.first ?? devices[0]
            let listing = devices.map { "  \($0.id)\($0.info["model"].map { " (\($0))" } ?? "")" }.joined(separator: "\n")
            await out.yield(MessageBlock(status: .warn, "Multiple Android devices found — targeting \(target.id). Use --android-serial to select a different device:\n\(listing)"))
            return target.id
        }

        // Explicit device specified — verify it exists
        let devices = try await getAndroidDevices()
        if devices.contains(where: { $0.id == androidSerial }) {
            return androidSerial
        }
        // No matching device
        let listing = devices.isEmpty
            ? "No connected Android devices or emulators were found."
            : "Connected devices:\n" + devices.map { "  \($0.id)\($0.info["model"].map { " (\($0))" } ?? "")" }.joined(separator: "\n")
        throw DevicesCommand.DevicesCommandError(errorDescription: "Android device '\(androidSerial)' not found. \(listing)")
    }

    /// Wait for an Android device to finish booting by polling `sys.boot_completed`.
    /// - Parameters:
    ///   - adb: Path to the `adb` binary.
    ///   - additionalEnvironment: Environment variables (should include `ANDROID_SERIAL` when targeting a specific device).
    ///   - timeout: Maximum seconds to wait. Pass `0` to skip waiting entirely.
    func waitForDeviceBoot(adb: String, additionalEnvironment: [String: String], timeout: Int, with out: MessageQueue) async throws {
        guard timeout > 0 else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            do {
                let result = try await run(with: out, "Waiting for device boot", [adb, "shell", "getprop", "sys.boot_completed"], additionalEnvironment: additionalEnvironment, watch: false, permitFailure: true)
                switch result {
                case .success(let output):
                    let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    await out.write(status: .warn, "success running adb shell: STDOUT=\(stdout) STDERR=\(stderr)")
                    if output.exitCode == 0 && (stdout == "1" || stdout == "") {
                        // for some reason on the GitHub CI, this is blank when the emulator has booted successfully
                        return
                    }
                case .failure(let error):
                    await out.write(status: .warn, "error running adb shell: \(error)")
                }
            } catch {
                await out.write(status: .warn, "process error running adb shell: \(error)")
            }
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        throw DevicesCommand.DevicesCommandError(errorDescription: "Timed out after \(timeout)s waiting for Android device to finish booting. Use --android-connect-timeout to increase the wait time, or check that the emulator is running.")
    }
}

/**
 ```
 adb devices -l
 List of devices attached
 emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
 
 xcrun simctl list devices booted iOS --json
 {
   "devices" : {
     "com.apple.CoreSimulator.SimRuntime.iOS-17-2" : [

     ],
     "com.apple.CoreSimulator.SimRuntime.iOS-15-5" : [

     ],
     "com.apple.CoreSimulator.SimRuntime.iOS-17-0" : [
       {
         "lastBootedAt" : "2024-01-26T14:46:09Z",
         "dataPath" : "\/Users\/marc\/Library\/Developer\/CoreSimulator\/Devices\/15D3857C-12C8-4FB8-9CB5-7D79E4CC0748\/data",
         "dataPathSize" : 7652925440,
         "logPath" : "\/Users\/marc\/Library\/Logs\/CoreSimulator\/15D3857C-12C8-4FB8-9CB5-7D79E4CC0748",
         "udid" : "15D3857C-12C8-4FB8-9CB5-7D79E4CC0748",
         "isAvailable" : true,
         "logPathSize" : 827392,
         "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-14",
         "state" : "Booted",
         "name" : "iPhone 14"
       }
     ],
     "com.apple.CoreSimulator.SimRuntime.iOS-17-4" : [

     ]
   }
 }

 xcrun devicectl list devices --timeout 5 --json-output -
 Devices:
 Name             Hostname                                     Identifier                             State                Model
 --------------   ------------------------------------------   ------------------------------------   ------------------   ---------------------------
 iPhone 12 mini   00008101-000569C93E90001E.coredevice.local   C85D41ED-3647-48D1-974E-30A53F3E629A   available (paired)   iPhone 12 mini (iPhone13,1)
 {
   "info" : {
     "arguments" : [
       "devicectl",
       "list",
       "devices",
       "--timeout",
       "5",
       "--json-output",
       "-"
     ],
     "commandType" : "devicectl.list.devices",
     "environment" : {
       "TERM" : "xterm-256color"
     },
     "jsonVersion" : 2,
     "outcome" : "success",
     "version" : "355.18"
   },
   "result" : {
     "devices" : [
       {
         "capabilities" : [
           {
             "featureIdentifier" : "com.apple.coredevice.feature.unpairdevice",
             "name" : "Unpair Device"
           },
           {
             "featureIdentifier" : "com.apple.coredevice.feature.connectdevice",
             "name" : "Connect to Device"
           },
           {
             "featureIdentifier" : "com.apple.coredevice.feature.acquireusageassertion",
             "name" : "Acquire Usage Assertion"
           }
         ],
         "connectionProperties" : {
           "authenticationType" : "manualPairing",
           "isMobileDeviceOnly" : false,
           "lastConnectionDate" : "2024-01-26T19:47:42.165Z",
           "pairingState" : "paired",
           "potentialHostnames" : [
             "00008101-000569C93E90001E.coredevice.local",
             "C85D41ED-3647-48D1-974E-30A53F3E629A.coredevice.local"
           ],
           "transportType" : "localNetwork",
           "tunnelState" : "disconnected",
           "tunnelTransportProtocol" : "tcp"
         },
         "deviceProperties" : {
           "bootedFromSnapshot" : true,
           "bootedSnapshotName" : "com.apple.os.update-A9C6E25B91A2CCBF017E6E83F8F9759EF7B827A61F149AE0261CAE9C81216A60069394AAED3A5B13AE40035F07673F27",
           "ddiServicesAvailable" : false,
           "developerModeStatus" : "enabled",
           "hasInternalOSBuild" : false,
           "name" : "iPhone 12 mini",
           "osBuildUpdate" : "21D50",
           "osVersionNumber" : "17.3",
           "rootFileSystemIsWritable" : false
         },
         "hardwareProperties" : {
           "cpuType" : {
             "name" : "arm64e",
             "subType" : 2,
             "type" : 16777228
           },
           "deviceType" : "iPhone",
           "ecid" : 1523687942520862,
           "hardwareModel" : "D52gAP",
           "internalStorageCapacity" : 64000000000,
           "isProductionFused" : true,
           "marketingName" : "iPhone 12 mini",
           "platform" : "iOS",
           "productType" : "iPhone13,1",
           "reality" : "physical",
           "serialNumber" : "F4HDM09Q0GRG",
           "supportedCPUTypes" : [
             {
               "name" : "arm64e",
               "subType" : 2,
               "type" : 16777228
             },
             {
               "name" : "arm64",
               "subType" : 0,
               "type" : 16777228
             },
             {
               "name" : "arm64",
               "subType" : 1,
               "type" : 16777228
             },
             {
               "name" : "arm64_32",
               "subType" : 1,
               "type" : 33554444
             }
           ],
           "supportedDeviceFamilies" : [
             1
           ],
           "thinningProductType" : "iPhone13,1",
           "udid" : "00008101-000569C93E90001E"
         },
         "identifier" : "C85D41ED-3647-48D1-974E-30A53F3E629A",
         "visibilityClass" : "default"
       }
     ]
   }
 }


 ~/Library/Android/sdk/tools/emulator -list-avds
 Nexus_6_API_29
 Pixel_5_API_34
 Pixel_6_API_33
 Pixel_6_API_34
 Resizable_Experimental_API_33

 ```

 */
