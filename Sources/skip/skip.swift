// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import SkipDrive

#if os(macOS)
/// Command-line runner for the `skip` tool.
@available(macOS 13, macCatalyst 16, *)
@main public struct SkipMain {
    static func main() async throws {
        await SkipDriver.main()
    }
}
#endif
