import Foundation
import ArgumentParser
import SkipSyntax
#if canImport(FoundationNetworking)
import FoundationNetworking // for non-Darwin
#endif
#if canImport(FoundationXML)
import FoundationXML // for non-Darwin
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct UpgradeCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "upgrade",
        abstract: "Upgrade to the latest Skip version using Homebrew",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    func performCommand(with out: MessageQueue) async throws {
        let latestSkipVersion = await checkSkipUpdates(with: out)
        if latestSkipVersion == skipVersion {
            await out.yield(MessageBlock(status: .pass, "Skip \(skipVersion) is up to date."))
        } else if let latestSkipVersion = latestSkipVersion {
            try await run(with: out, "Upgrade Skip to \(latestSkipVersion)", ["brew", "upgrade", "skip"], additionalEnvironment: ["HOMEBREW_AUTO_UPDATE_SECS": "0"])
        }
    }
}

extension SkipCommand {
    /// Checks the https://source.skip.tools/skip/releases.atom page and returns the semantic version contained in the title of the first entry (i.e., the latest release of Skip)
    func checkSkipUpdates(with out: MessageQueue) async -> String? {
        try? await outputOptions.monitor(with: out, "Check Skip Updates", resultHandler: { result in
            (result, MessageBlock(status: result?.messageStatusAny, "Check Skip Updates: \((try? result?.get()) ?? "?")"))
        }) { loggingHandler in
            try await fetchLatestRelease(from: URL(string: "https://source.skip.tools/skip/releases.atom")!)
        }.get()
    }

    /// Grabs an Atom XML feed of releases and returns the first title.
    private func fetchLatestRelease(from atomURL: URL) async throws -> String? {
        let (data, response) = try await URLSession.shared.data(from: atomURL, delegate: URLSessionTaskDelegate?.none)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            throw SkipUpdateError(errorDescription: "Update check from \(atomURL.absoluteString) returned error: \(code)")
        }

        #if canImport(AppKit) || canImport(FoundationXML)
        // parse the Atom XML and get the latest version, which is the title of the first entry
        let document = try XMLDocument(data: data)
        return document.rootElement()?.elements(forName: "entry").first?.elements(forName: "title").first?.stringValue
        #else
        // no XMLDocument on iOS, so do it the hard way with a CFXMLParser…
        throw SkipUpdateError(errorDescription: "Cannot check for updates from iOS")
        #endif
    }

}

struct SkipUpdateError : LocalizedError {
    public var errorDescription: String?
}
