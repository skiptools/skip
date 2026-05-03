// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic

#if canImport(FoundationXML)
import FoundationXML
#endif

#if canImport(SkipDriveExternal)
import SkipDriveExternal
extension MetaIndexCommand : GradleHarness { }
fileprivate let metaCommandEnabled = true
#else
fileprivate let metaCommandEnabled = false
#endif

// MARK: - Container Command

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct MetaCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "meta",
        abstract: "App metadata and SBOM tools",
        discussion: """
        Commands for generating app metadata catalogs and Software Bill of Materials (SBOM).
        """,
        shouldDisplay: metaCommandEnabled,
        subcommands: [
            MetaIndexCommand.self,
            SBOMCommand.self,
        ])
}

// MARK: - Generate Subcommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct MetaIndexCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Generate a JSON metadata index for the app",
        usage: """
# generate app metadata to stdout
skip meta index

# write to a file
skip meta index -O appindex.json

# include SBOM in the output
skip meta index --sbom -O appindex.json
""",
        discussion: """
Generate a structured JSON document containing all user-facing metadata for a Skip app, \
including localized titles and descriptions from fastlane metadata, app permissions \
from Info.plist and AndroidManifest.xml, version information from Skip.env, \
and optionally a Software Bill of Materials (SBOM) for each platform.

The output uses Android/Play Store locale codes (e.g. "zh-CN" instead of Apple's "zh-Hans").
""",
        shouldDisplay: metaCommandEnabled)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("O"), .customLong("catalog-output")], help: ArgumentHelp("Write catalog JSON to the given file instead of stdout", valueName: "path"))
    var catalogOutput: String?

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Flag(help: ArgumentHelp("Include SBOM in the output"))
    var sbom: Bool = false

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runMetaGenerate(with: out)
        }
    }

    func runMetaGenerate(with out: MessageQueue) async throws {
        let projectURL = URL(fileURLWithPath: self.project).standardized
        let catalog = try await generateAppCatalog(projectURL: projectURL, includeSBOM: sbom, with: out)
        let jsonData = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

        if let outputPath = catalogOutput {
            let outputURL = URL(fileURLWithPath: outputPath)
            try jsonData.write(to: outputURL)
            await out.write(status: .pass, "Wrote app catalog to \(outputPath)")
        } else {
            // Write to stdout
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        }
    }

    // MARK: - Catalog Generation

    func generateAppCatalog(projectURL: URL, includeSBOM: Bool, with out: MessageQueue) async throws -> [String: Any] {
        let packageJSON = try await parseSwiftPackage(with: out, at: projectURL.path)
        return try await AppIndexGenerator.generateAppIndex(projectURL: projectURL, packageJSON: packageJSON, includeSBOM: includeSBOM, command: self, out: out)
    }

    // MARK: - Git Origin Parsing

    /// Parse the git remote origin URL from `.git/config`.
    func parseGitOriginURL(projectRoot: URL) -> String? {
        let gitConfig = projectRoot.appendingPathComponent(".git/config")
        guard let contents = try? String(contentsOf: gitConfig, encoding: .utf8) else { return nil }

        var inOrigin = false
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inOrigin = trimmed == "[remote \"origin\"]"
                continue
            }
            if inOrigin && trimmed.hasPrefix("url") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    /// Convert a git remote URL to an HTTPS browse URL.
    /// Handles both HTTPS and SSH formats:
    ///   https://github.com/Org/Repo.git → https://github.com/Org/Repo
    ///   git@github.com:Org/Repo.git     → https://github.com/Org/Repo
    static func gitRemoteToHTTPS(_ remoteURL: String) -> String {
        var url = remoteURL
        // Convert SSH to HTTPS
        if url.hasPrefix("git@") {
            url = url.replacingOccurrences(of: "git@", with: "https://")
            if let colonRange = url.range(of: ":", range: url.index(url.startIndex, offsetBy: 8)..<url.endIndex) {
                url = url.replacingCharacters(in: colonRange, with: "/")
            }
        }
        // Strip trailing .git
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }
        return url
    }

    // MARK: - License Detection

    /// Detect the SPDX license identifier from a LICENSE file in the project root.
    func detectLicense(projectRoot: URL) -> String? {
        let fm = FileManager.default
        let candidates = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENSE.GPL", "LICENSE.AGPL", "LICENSE.MPL", "LICENCE", "LICENCE.md", "LICENCE.txt", "LICENSE-MIT", "LICENSE-APACHE", "COPYING", "COPYING.md"]
        for name in candidates {
            let url = projectRoot.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lower = content.lowercased()
            // Check for common SPDX-identifiable licenses by their distinctive text
            if lower.contains("gnu general public license") && lower.contains("version 3") {
                return lower.contains("affero") ? "AGPL-3.0-only" : "GPL-3.0-only"
            }
            if lower.contains("gnu general public license") && lower.contains("version 2") {
                return "GPL-2.0-only"
            }
            if lower.contains("gnu lesser general public license") {
                return lower.contains("version 3") ? "LGPL-3.0-only" : "LGPL-2.1-only"
            }
            if lower.contains("mozilla public license") && lower.contains("version 2") {
                return "MPL-2.0"
            }
            if lower.contains("apache license") && lower.contains("version 2") {
                return "Apache-2.0"
            }
            if lower.contains("mit license") || lower.contains("permission is hereby granted, free of charge") {
                return "MIT"
            }
            if lower.contains("bsd 2-clause") || (lower.contains("redistribution and use") && !lower.contains("neither the name")) {
                return "BSD-2-Clause"
            }
            if lower.contains("bsd 3-clause") || (lower.contains("redistribution and use") && lower.contains("neither the name")) {
                return "BSD-3-Clause"
            }
            if lower.contains("the unlicense") || lower.contains("this is free and unencumbered software") {
                return "Unlicense"
            }
            if lower.contains("isc license") {
                return "ISC"
            }
            // Check for SPDX header in the file itself
            if let range = content.range(of: "SPDX-License-Identifier:") {
                let start = range.upperBound
                let remaining = content[start...].trimmingCharacters(in: .whitespaces)
                let id = remaining.components(separatedBy: .whitespacesAndNewlines).first ?? ""
                if !id.isEmpty { return id }
            }
            return nil
        }
        return nil
    }

    // MARK: - Skip.env Parsing

    func parseSkipEnv(at url: URL) throws -> [String: String] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var env: [String: String] = [:]
        for (key, value) in parseXCConfig(contents: contents) {
            env[key] = value
        }
        return env
    }

    // MARK: - iOS Metadata

    func buildIOSMetadata(appProject: AppProjectLayout, projectRoot: URL, productName: String, bundleId: String, version: String, buildNumber: String, appleStoreId: String?) throws -> [String: Any] {
        var ios: [String: Any] = [
            "bundleIdentifier": bundleId,
            "version": version,
            "buildNumber": buildNumber,
        ]

        if let appleStoreId = appleStoreId, !appleStoreId.isEmpty {
            ios["channels"] = [
                "appleappstore": [
                    "id": appleStoreId,
                    "url": "https://apps.apple.com/app/id\(appleStoreId)",
                ] as [String: Any]
            ] as [String: Any]
        }

        // Parse Info.plist and Entitlements into a "metadata" dictionary
        var metadata: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: appProject.darwinInfoPlist.path) {
            let infoPlistData = try parseInfoPlist(at: appProject.darwinInfoPlist)
            if !infoPlistData.isEmpty {
                metadata["infoPlist"] = infoPlistData
            }
            let xcstringsURL = FileManager.default.fileExists(atPath: appProject.darwinInfoPlistXcstrings.path) ? appProject.darwinInfoPlistXcstrings : nil
            let permissions = try extractIOSPermissions(at: appProject.darwinInfoPlist, xcstringsURL: xcstringsURL)
            if !permissions.isEmpty {
                ios["permissions"] = permissions
            }
        }
        if FileManager.default.fileExists(atPath: appProject.darwinEntitlementsPlist.path) {
            let entitlements = try parseEntitlements(at: appProject.darwinEntitlementsPlist)
            if !entitlements.isEmpty {
                metadata["entitlements"] = entitlements
            }
        }
        if !metadata.isEmpty {
            ios["metadata"] = metadata
        }

        // Parse localized fastlane metadata
        let localizedMeta = parseFastlaneMetadata(folder: appProject.darwinFastlaneMetadataFolder, platform: .ios)
        for (key, value) in localizedMeta {
            ios[key] = value
        }

        // Assets: icon, screenshots
        var assets: [String: Any] = [:]
        if let iconRef = findLargestPNG(in: appProject.darwinAppIconFolder, relativeTo: projectRoot) {
            assets["icon"] = iconRef.asDictionary
        }
        let screenshotDir = appProject.darwinFastlaneFolder.appendingPathComponent("screenshots")
        let screenshots = collectLocalizedScreenshots(folder: screenshotDir, relativeTo: projectRoot, convention: .apple)
        if !screenshots.isEmpty {
            assets["screenshots"] = screenshots
        }
        if !assets.isEmpty {
            ios["assets"] = assets
        }

        return ios
    }

    // MARK: - Android Metadata

    func buildAndroidMetadata(appProject: AppProjectLayout, projectRoot: URL, productName: String, bundleId: String, androidAppId: String?, version: String, buildNumber: String, googlePlayStoreId: String?) throws -> [String: Any] {
        let effectiveAppId = androidAppId ?? bundleId.replacingOccurrences(of: "-", with: "_")

        var android: [String: Any] = [
            "applicationId": effectiveAppId,
            "version": version,
            "buildNumber": buildNumber,
        ]

        do {
            let playId = (googlePlayStoreId?.isEmpty == false ? googlePlayStoreId : nil) ?? effectiveAppId
            android["channels"] = [
                "googleplaystore": [
                    "id": playId,
                    "url": "https://play.google.com/store/apps/details?id=\(playId)",
                ] as [String: Any]
            ] as [String: Any]
        }

        // Parse AndroidManifest.xml for permissions and metadata
        if FileManager.default.fileExists(atPath: appProject.androidManifest.path) {
            let manifestPermissions = try extractAndroidPermissions(at: appProject.androidManifest)
            if !manifestPermissions.isEmpty {
                android["permissions"] = manifestPermissions
            }
            let manifestMeta = try parseAndroidManifest(at: appProject.androidManifest)
            if !manifestMeta.isEmpty {
                android["metadata"] = ["manifest": manifestMeta] as [String: Any]
            }
        }

        // Parse localized fastlane metadata
        let localizedMeta = parseFastlaneMetadata(folder: appProject.androidFastlaneMetadataFolder, platform: .android)
        for (key, value) in localizedMeta {
            android[key] = value
        }

        // Assets: icon, featureGraphic, screenshots
        var assets: [String: Any] = [:]
        let androidIconURL = appProject.androidFastlaneMetadataFolder.appendingPathComponent("en-US/images/icon.png")
        if let iconRef = ImageResourceRef.from(pngURL: androidIconURL, relativeTo: projectRoot) {
            assets["icon"] = iconRef.asDictionary
        }
        let featureGraphics = collectLocalizedImages(named: "featureGraphic.png", subpath: "images", metadataFolder: appProject.androidFastlaneMetadataFolder, relativeTo: projectRoot, convention: .google)
        if !featureGraphics.isEmpty {
            assets["featureGraphic"] = featureGraphics
        }
        let screenshots = collectAndroidScreenshots(metadataFolder: appProject.androidFastlaneMetadataFolder, relativeTo: projectRoot, convention: .google)
        if !screenshots.isEmpty {
            assets["screenshots"] = screenshots
        }
        if !assets.isEmpty {
            android["assets"] = assets
        }

        return android
    }

    // MARK: - Info.plist Parsing

    func parseInfoPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw error("Info.plist at \(url.path) is not a valid dictionary plist")
        }
        var result: [String: Any] = [:]
        let includeKeys = ["CFBundleName", "CFBundleDisplayName", "CFBundleShortVersionString", "CFBundleVersion",
                           "ITSAppUsesNonExemptEncryption", "UIRequiredDeviceCapabilities",
                           "UISupportedInterfaceOrientations", "UILaunchStoryboardName",
                           "LSApplicationQueriesSchemes", "CFBundleURLTypes"]
        for key in includeKeys {
            if let value = plist[key] {
                result[key] = value
            }
        }
        return result
    }

    func extractIOSPermissions(at plistURL: URL, xcstringsURL: URL?, defaultLocale: String = "en") throws -> [[String: Any]] {
        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw error("Info.plist at \(plistURL.path) is not a valid dictionary plist")
        }

        // Parse InfoPlist.xcstrings for translations if available
        let xcstringsTranslations = xcstringsURL.flatMap { parseXcstrings(at: $0) } ?? [:]

        var permissions: [[String: Any]] = []
        for (key, value) in plist {
            guard key.hasSuffix("UsageDescription"), let defaultDesc = value as? String else { continue }

            var descriptions: [String: String] = [defaultLocale: defaultDesc]

            // Merge translations from xcstrings
            if let localizations = xcstringsTranslations[key] {
                for (locale, translation) in localizations {
                    let normalizedLocale = Self.normalizeLocale(locale, convention: .apple)
                    descriptions[normalizedLocale] = translation
                }
            }

            permissions.append([
                "key": key,
                "description": descriptions,
            ] as [String: Any])
        }

        return permissions.sorted { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }
    }

    // MARK: - Xcstrings Parsing

    /// Parse an .xcstrings file and return a map of key → { locale → translated string }.
    func parseXcstrings(at url: URL) -> [String: [String: String]]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any] else {
            return nil
        }

        var result: [String: [String: String]] = [:]
        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            var translations: [String: String] = [:]
            for (locale, locValue) in localizations {
                if let locDict = locValue as? [String: Any],
                   let stringUnit = locDict["stringUnit"] as? [String: Any],
                   let translated = stringUnit["value"] as? String {
                    translations[locale] = translated
                }
            }
            if !translations.isEmpty {
                result[key] = translations
            }
        }
        return result
    }

    // MARK: - Entitlements Parsing

    func parseEntitlements(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw error("Entitlements.plist at \(url.path) is not a valid dictionary plist")
        }
        return plist
    }

    // MARK: - AndroidManifest.xml Parsing

    func parseAndroidManifest(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let delegate = AndroidManifestParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            let parseError = parser.parserError.map { ": \($0.localizedDescription)" } ?? ""
            throw error("Failed to parse AndroidManifest.xml at \(url.path)\(parseError)")
        }
        return delegate.metadata
    }

    func extractAndroidPermissions(at url: URL) throws -> [[String: String]] {
        let data = try Data(contentsOf: url)
        let delegate = AndroidManifestParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            let parseError = parser.parserError.map { ": \($0.localizedDescription)" } ?? ""
            throw error("Failed to parse AndroidManifest.xml at \(url.path)\(parseError)")
        }
        return delegate.permissions
    }

    // MARK: - Fastlane Metadata Parsing

    enum MetadataPlatform {
        case ios
        case android
    }

    /// Metadata files we extract from fastlane directories.
    /// iOS: Darwin/fastlane/metadata/{locale}/{file}.txt
    /// Android: Android/fastlane/metadata/android/{locale}/{file}.txt
    static let iosMetadataFiles = ["title", "subtitle", "description", "keywords", "release_notes",
                                   "privacy_url", "support_url", "marketing_url"]
    static let androidMetadataFiles = ["title", "short_description", "full_description"]

    func parseFastlaneMetadata(folder: URL, platform: MetadataPlatform) -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return [:] }
        guard let locales = try? fm.contentsOfDirectory(atPath: folder.path) else { return [:] }

        let metadataFiles = platform == .ios ? Self.iosMetadataFiles : Self.androidMetadataFiles
        var stringResults: [String: [String: String]] = [:]
        var arrayResults: [String: [String: [String]]] = [:]

        for locale in locales.sorted() {
            let localeDir = folder.appendingPathComponent(locale)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: localeDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let convention: LocaleConvention = platform == .ios ? .apple : .google
            let normalizedLocale = Self.normalizeLocale(locale, convention: convention)

            for fileName in metadataFiles {
                let filePath = localeDir.appendingPathComponent(fileName + ".txt")
                guard fm.fileExists(atPath: filePath.path) else { continue }
                guard let content = try? String(contentsOf: filePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                      !content.isEmpty else { continue }

                let key = Self.normalizeMetadataKey(fileName, platform: platform)

                // Keywords are split into arrays
                if key == "keywords" {
                    let keywords = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if arrayResults[key] == nil { arrayResults[key] = [:] }
                    arrayResults[key]?[normalizedLocale] = keywords
                } else {
                    if stringResults[key] == nil { stringResults[key] = [:] }
                    stringResults[key]?[normalizedLocale] = content
                }
            }
        }

        var result: [String: Any] = [:]
        for (key, value) in stringResults { result[key] = value }
        for (key, value) in arrayResults { result[key] = value }
        return result
    }

    /// Normalize a metadata file name to a common key across platforms.
    static func normalizeMetadataKey(_ fileName: String, platform: MetadataPlatform) -> String {
        switch fileName {
        case "full_description": return "description"
        case "short_description": return "subtitle"
        case "release_notes", "version_whats_new": return "releaseNotes"
        case "privacy_url": return "privacyURL"
        case "support_url": return "supportURL"
        case "marketing_url": return "marketingURL"
        default: return fileName
        }
    }

    // MARK: - Locale Normalization

    /// The platform convention for locale codes in fastlane metadata directories.
    enum LocaleConvention {
        /// Apple App Store locale codes (e.g. "ar-SA", "zh-Hans", "en-US").
        /// Reference: https://docs.fastlane.tools/actions/appstore/#available-language-codes
        case apple
        /// Google Play Store locale codes (e.g. "ar", "zh-CN", "en-US").
        /// Reference: https://support.google.com/googleplay/android-developer/answer/9844778
        case google
    }

    /// Normalize a platform-specific locale code to BCP 47 canonical form.
    ///
    /// - Parameters:
    ///   - locale: The locale code from the platform's fastlane metadata directory.
    ///   - convention: Which platform's naming convention the locale uses.
    /// - Returns: The canonical BCP 47 locale code.
    ///
    /// To update the mapping tables when Apple or Google add or change their language codes:
    /// 1. Check the platform reference URL listed in each table's doc comment.
    /// 2. Add the new code to the appropriate `normalizeLocaleApple()` or `normalizeLocaleGoogle()` table.
    /// 3. Map it to the BCP 47 canonical form (typically the shortest unambiguous subtag).
    /// 4. Update the test cases in `testLocaleNormalization()` to cover the new code.
    static func normalizeLocale(_ locale: String, convention: LocaleConvention) -> String {
        switch convention {
        case .apple:  return normalizeLocaleApple(locale)
        case .google: return normalizeLocaleGoogle(locale)
        }
    }

    /// Normalize an Apple App Store locale code to BCP 47 canonical form.
    ///
    /// Apple locale codes used in fastlane metadata directories:
    /// ar-SA, ca, cs, da, de-DE, el, en-AU, en-CA, en-GB, en-US, es-ES, es-MX,
    /// fi, fr-CA, fr-FR, he, hi, hr, hu, id, it, ja, ko, ms, nl-NL, no, pl,
    /// pt-BR, pt-PT, ro, ru, sk, sv, th, tr, uk, vi, zh-Hans, zh-Hant
    ///
    /// Source: https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes and https://docs.fastlane.tools/actions/appstore/#available-language-codes
    static func normalizeLocaleApple(_ locale: String) -> String {
        let appleToCanonical: [String: String] = [
            "ar-SA":   "ar",       // Arabic (Saudi Arabia) → Arabic
            "ca":      "ca",       // Catalan
            "cs":      "cs",       // Czech
            "da":      "da",       // Danish
            "de-DE":   "de",       // German (Germany) → German
            "el":      "el",       // Greek
            "en-AU":   "en-AU",    // English (Australia)
            "en-CA":   "en-CA",    // English (Canada)
            "en-GB":   "en-GB",    // English (UK)
            "en-US":   "en",       // English (US) → English (default)
            "es-ES":   "es",       // Spanish (Spain) → Spanish
            "es-MX":   "es-MX",    // Spanish (Mexico)
            "fi":      "fi",       // Finnish
            "fr-CA":   "fr-CA",    // French (Canada)
            "fr-FR":   "fr",       // French (France) → French
            "he":      "he",       // Hebrew
            "hi":      "hi",       // Hindi
            "hr":      "hr",       // Croatian
            "hu":      "hu",       // Hungarian
            "id":      "id",       // Indonesian
            "it":      "it",       // Italian
            "ja":      "ja",       // Japanese
            "ko":      "ko",       // Korean
            "ms":      "ms",       // Malay
            "nl-NL":   "nl",       // Dutch (Netherlands) → Dutch
            "no":      "no",       // Norwegian
            "pl":      "pl",       // Polish
            "pt-BR":   "pt-BR",    // Portuguese (Brazil)
            "pt-PT":   "pt",       // Portuguese (Portugal) → Portuguese
            "ro":      "ro",       // Romanian
            "ru":      "ru",       // Russian
            "sk":      "sk",       // Slovak
            "sv":      "sv",       // Swedish
            "th":      "th",       // Thai
            "tr":      "tr",       // Turkish
            "uk":      "uk",       // Ukrainian
            "vi":      "vi",       // Vietnamese
            "zh-Hans": "zh-Hans",  // Chinese Simplified
            "zh-Hant": "zh-Hant",  // Chinese Traditional
        ]

        return appleToCanonical[locale] ?? locale
    }

    /// Normalize a Google Play Store locale code to BCP 47 canonical form.
    ///
    /// Google locale codes used in fastlane metadata directories:
    /// af, sq, am, ar, hy-AM, az-AZ, bn-BD, eu-ES, be, bg, my-MM, ca, zh-HK,
    /// zh-CN, zh-TW, hr, cs-CZ, da-DK, nl-NL, en-AU, en-CA, en-US, en-GB,
    /// en-IN, en-SG, en-ZA, et, fil, fi-FI, fr-CA, fr-FR, gl-ES, ka-GE, de-DE,
    /// el-GR, gu, iw-IL, hi-IN, hu-HU, is-IS, id, it-IT, ja-JP, kn-IN, kk,
    /// km-KH, ko-KR, ky-KG, lo-LA, lv, lt, mk-MK, ms-MY, ms, ml-IN, mr-IN,
    /// mn-MN, ne-NP, no-NO, fa, fa-AE, fa-AF, fa-IR, pl-PL, pt-BR, pt-PT, pa,
    /// ro, rm, ru-RU, sr, si-LK, sk, sl, es-419, es-ES, es-US, sw, sv-SE,
    /// ta-IN, te-IN, th, tr-TR, uk, ur, vi
    ///
    /// Source: https://support.google.com/googleplay/android-developer/answer/9844778
    static func normalizeLocaleGoogle(_ locale: String) -> String {
        let googleToCanonical: [String: String] = [
            "af":      "af",       // Afrikaans
            "am":      "am",       // Amharic
            "ar":      "ar",       // Arabic
            "az-AZ":   "az",       // Azerbaijani
            "be":      "be",       // Belarusian
            "bg":      "bg",       // Bulgarian
            "bn-BD":   "bn",       // Bengali
            "ca":      "ca",       // Catalan
            "cs-CZ":   "cs",       // Czech
            "da-DK":   "da",       // Danish
            "de-DE":   "de",       // German
            "el-GR":   "el",       // Greek
            "en-AU":   "en-AU",    // English (Australia)
            "en-CA":   "en-CA",    // English (Canada)
            "en-GB":   "en-GB",    // English (UK)
            "en-IN":   "en-IN",    // English (India)
            "en-SG":   "en-SG",    // English (Singapore)
            "en-US":   "en",       // English (US) → English (default)
            "en-ZA":   "en-ZA",    // English (South Africa)
            "es-419":  "es-419",   // Spanish (Latin America)
            "es-ES":   "es",       // Spanish (Spain) → Spanish
            "es-US":   "es-US",    // Spanish (US)
            "et":      "et",       // Estonian
            "eu-ES":   "eu",       // Basque
            "fa-AE":   "fa",       // Persian (UAE) → Persian
            "fa-AF":   "fa",       // Persian (Afghanistan) → Persian
            "fa-IR":   "fa",       // Persian (Iran) → Persian
            "fa":      "fa",       // Persian
            "fi-FI":   "fi",       // Finnish
            "fil":     "fil",      // Filipino
            "fr-CA":   "fr-CA",    // French (Canada)
            "fr-FR":   "fr",       // French (France) → French
            "gl-ES":   "gl",       // Galician
            "gu":      "gu",       // Gujarati
            "hi-IN":   "hi",       // Hindi
            "hr":      "hr",       // Croatian
            "hu-HU":   "hu",       // Hungarian
            "hy-AM":   "hy",       // Armenian
            "id":      "id",       // Indonesian
            "is-IS":   "is",       // Icelandic
            "it-IT":   "it",       // Italian
            "iw-IL":   "he",       // Hebrew (legacy "iw" code)
            "ja-JP":   "ja",       // Japanese
            "ka-GE":   "ka",       // Georgian
            "kk":      "kk",       // Kazakh
            "km-KH":   "km",       // Khmer
            "kn-IN":   "kn",       // Kannada
            "ko-KR":   "ko",       // Korean
            "ky-KG":   "ky",       // Kyrgyz
            "lo-LA":   "lo",       // Lao
            "lt":      "lt",       // Lithuanian
            "lv":      "lv",       // Latvian
            "mk-MK":   "mk",       // Macedonian
            "ml-IN":   "ml",       // Malayalam
            "mn-MN":   "mn",       // Mongolian
            "mr-IN":   "mr",       // Marathi
            "ms-MY":   "ms",       // Malay (Malaysia) → Malay
            "ms":      "ms",       // Malay
            "my-MM":   "my",       // Burmese
            "ne-NP":   "ne",       // Nepali
            "nl-NL":   "nl",       // Dutch
            "no-NO":   "no",       // Norwegian
            "pa":      "pa",       // Punjabi
            "pl-PL":   "pl",       // Polish
            "pt-BR":   "pt-BR",    // Portuguese (Brazil)
            "pt-PT":   "pt",       // Portuguese (Portugal) → Portuguese
            "rm":      "rm",       // Romansh
            "ro":      "ro",       // Romanian
            "ru-RU":   "ru",       // Russian
            "si-LK":   "si",       // Sinhala
            "sk":      "sk",       // Slovak
            "sl":      "sl",       // Slovenian
            "sq":      "sq",       // Albanian
            "sr":      "sr",       // Serbian
            "sv-SE":   "sv",       // Swedish
            "sw":      "sw",       // Swahili
            "ta-IN":   "ta",       // Tamil
            "te-IN":   "te",       // Telugu
            "th":      "th",       // Thai
            "tr-TR":   "tr",       // Turkish
            "uk":      "uk",       // Ukrainian
            "ur":      "ur",       // Urdu
            "vi":      "vi",       // Vietnamese
            "zh-CN":   "zh-Hans",  // Chinese (China) → Chinese Simplified
            "zh-HK":   "zh-Hant",  // Chinese (Hong Kong) → Chinese Traditional
            "zh-TW":   "zh-Hant",  // Chinese (Taiwan) → Chinese Traditional
        ]

        return googleToCanonical[locale] ?? locale
    }
}

// MARK: - Image Resource Reference

public struct ImageResourceRef: Codable, Equatable, Sendable {
    public var mimeType: String?
    public var location: String
    public var size: Int64
    public var digest: String
    public var width: Int
    public var height: Int
    public var caption: String?

    /// Convert to a dictionary for JSON serialization.
    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "location": location,
            "size": size,
            "digest": digest,
            "width": width,
            "height": height,
        ]
        if let mimeType = mimeType { dict["mimeType"] = mimeType }
        if let caption = caption { dict["caption"] = caption }
        return dict
    }

    /// Create an ImageResourceRef from a PNG file URL, relative to the project root.
    static func from(pngURL: URL, relativeTo root: URL) -> ImageResourceRef? {
        guard let data = try? Data(contentsOf: pngURL) else { return nil }
        let fileSize = Int64(data.count)
        guard fileSize > 0 else { return nil }
        let hash = data.SHA256Hash()
        let (width, height) = parsePNGDimensions(data)
        let location = relativePath(from: root.standardized.path, to: pngURL.standardized.path)
        return ImageResourceRef(mimeType: "image/png", location: location, size: fileSize, digest: "sha256:\(hash)", width: width, height: height)
    }

    /// Parse width and height from a PNG file's IHDR chunk.
    /// PNG format: 8-byte signature, then IHDR chunk with 4-byte length, 4-byte type ("IHDR"),
    /// 4-byte width (big-endian), 4-byte height (big-endian).
    static func parsePNGDimensions(_ data: Data) -> (width: Int, height: Int) {
        // PNG signature is 8 bytes, then first chunk: 4 bytes length + 4 bytes "IHDR" + 4 bytes width + 4 bytes height
        // Minimum offset for width: 16, for height: 20
        guard data.count >= 24 else { return (0, 0) }
        // Verify PNG signature
        let sig: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        for i in 0..<8 {
            if data[i] != sig[i] { return (0, 0) }
        }
        // Width at offset 16, height at offset 20 (big-endian UInt32)
        let width = Int(data[16]) << 24 | Int(data[17]) << 16 | Int(data[18]) << 8 | Int(data[19])
        let height = Int(data[20]) << 24 | Int(data[21]) << 16 | Int(data[22]) << 8 | Int(data[23])
        return (width, height)
    }

}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension MetaIndexCommand {

    // MARK: - Icon Discovery

    /// Find the largest PNG file in a directory (used for iOS AppIcon.appiconset).
    func findLargestPNG(in folder: URL, relativeTo root: URL) -> ImageResourceRef? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return nil }
        guard let files = try? fm.contentsOfDirectory(atPath: folder.path) else { return nil }

        var largest: (url: URL, size: Int64)? = nil
        for file in files where file.hasSuffix(".png") {
            let fileURL = folder.appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attrs[.size] as? Int64 else { continue }
            if largest == nil || fileSize > largest!.size {
                largest = (fileURL, fileSize)
            }
        }

        guard let best = largest else { return nil }
        return ImageResourceRef.from(pngURL: best.url, relativeTo: root)
    }

    // MARK: - Localized Image Discovery

    /// Collect a single named image file across locale directories.
    /// Returns a locale → ImageResourceRef dictionary.
    /// Path: {metadataFolder}/{locale}/{subpath}/{fileName}
    func collectLocalizedImages(named fileName: String, subpath: String, metadataFolder: URL, relativeTo root: URL, convention: MetaIndexCommand.LocaleConvention) -> [String: [String: Any]] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: metadataFolder.path) else { return [:] }
        guard let locales = try? fm.contentsOfDirectory(atPath: metadataFolder.path) else { return [:] }

        var result: [String: [String: Any]] = [:]
        for locale in locales.sorted() {
            let imageURL = metadataFolder.appendingPathComponent(locale)
                .appendingPathComponent(subpath)
                .appendingPathComponent(fileName)
            if fm.fileExists(atPath: imageURL.path),
               let ref = ImageResourceRef.from(pngURL: imageURL, relativeTo: root) {
                result[MetaIndexCommand.normalizeLocale(locale, convention: convention)] = ref.asDictionary
            }
        }
        return result
    }

    // MARK: - Screenshot Discovery

    /// Collect localized screenshots from a fastlane screenshots directory.
    func collectLocalizedScreenshots(folder: URL, relativeTo root: URL, convention: MetaIndexCommand.LocaleConvention) -> [String: [[String: Any]]] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return [:] }
        guard let locales = try? fm.contentsOfDirectory(atPath: folder.path) else { return [:] }

        var result: [String: [[String: Any]]] = [:]

        for locale in locales.sorted() {
            let localeDir = folder.appendingPathComponent(locale)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: localeDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let normalizedLocale = MetaIndexCommand.normalizeLocale(locale, convention: convention)
            var refs: [[String: Any]] = []

            if let files = try? fm.contentsOfDirectory(atPath: localeDir.path) {
                for file in files.sorted() where file.hasSuffix(".png") {
                    let fileURL = localeDir.appendingPathComponent(file)
                    if let ref = ImageResourceRef.from(pngURL: fileURL, relativeTo: root) {
                        refs.append(ref.asDictionary)
                    }
                }
            }

            if !refs.isEmpty {
                result[normalizedLocale] = refs
            }
        }

        return result
    }

    /// Collect Android screenshots from Android/fastlane/metadata/android/{locale}/images/phoneScreenshots/*.png
    func collectAndroidScreenshots(metadataFolder: URL, relativeTo root: URL, convention: MetaIndexCommand.LocaleConvention) -> [String: [[String: Any]]] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: metadataFolder.path) else { return [:] }
        guard let locales = try? fm.contentsOfDirectory(atPath: metadataFolder.path) else { return [:] }

        var result: [String: [[String: Any]]] = [:]

        for locale in locales.sorted() {
            let screenshotDir = metadataFolder.appendingPathComponent(locale)
                .appendingPathComponent("images/phoneScreenshots")
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: screenshotDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let normalizedLocale = MetaIndexCommand.normalizeLocale(locale, convention: convention)
            var refs: [[String: Any]] = []

            if let files = try? fm.contentsOfDirectory(atPath: screenshotDir.path) {
                for file in files.sorted() where file.hasSuffix(".png") {
                    let fileURL = screenshotDir.appendingPathComponent(file)
                    if let ref = ImageResourceRef.from(pngURL: fileURL, relativeTo: root) {
                        refs.append(ref.asDictionary)
                    }
                }
            }

            if !refs.isEmpty {
                result[normalizedLocale] = refs
            }
        }

        return result
    }
}

// MARK: - Shared App Index Generator

/// Shared logic for generating an app index JSON document, used by both
/// `skip meta index` and `skip export --appindex`.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
enum AppIndexGenerator {
    static let appIndexFilename = "appindex.json"

    /// Generate the app index dictionary from a project.
    static func generateAppIndex<C: StreamingCommand & OutputOptionsCommand>(projectURL: URL, packageJSON: PackageManifest, includeSBOM: Bool, command: C, out: MessageQueue) async throws -> [String: Any] {
        let moduleNames = packageJSON.targets.compactMap(\.a).filter({ $0.type == "regular" }).filter({ $0.pluginUsages != nil }).map(\.name)
        guard let appModuleName = moduleNames.first else {
            throw AppIndexError(message: "No Skip module targets found in package \(packageJSON.name)")
        }

        let appProject = AppProjectLayout(moduleName: appModuleName, root: projectURL, check: AppProjectLayout.noURLChecks)
        let cmd = MetaIndexCommand()

        let env = try cmd.parseSkipEnv(at: appProject.skipEnv)

        let bundleId = env["PRODUCT_BUNDLE_IDENTIFIER"] ?? ""
        let version = env["MARKETING_VERSION"] ?? "0.0.1"
        let buildNumber = env["CURRENT_PROJECT_VERSION"] ?? "1"
        let productName = env["PRODUCT_NAME"] ?? appModuleName
        let androidAppId = env["ANDROID_APPLICATION_ID"]
        let appleStoreId = env["APPLE_APP_STORE_ID"]
        let googlePlayStoreId = env["GOOGLE_PLAY_STORE_ID"]

        var iosDict = try cmd.buildIOSMetadata(appProject: appProject, projectRoot: projectURL, productName: productName, bundleId: bundleId, version: version, buildNumber: buildNumber, appleStoreId: appleStoreId)
        var androidDict = try cmd.buildAndroidMetadata(appProject: appProject, projectRoot: projectURL, productName: productName, bundleId: bundleId, androidAppId: androidAppId, version: version, buildNumber: buildNumber, googlePlayStoreId: googlePlayStoreId)

        if includeSBOM {
            #if canImport(SkipDriveExternal)
            let outputDir = try AbsolutePath(validating: NSTemporaryDirectory())
            let sbomFiles = try await SBOMGenerator.generateSBOMFiles(generateIOS: true, generateAndroid: true, projectPath: projectURL.path, packageName: packageJSON.name, packageJSON: packageJSON, outputDirAbsolute: outputDir, command: command, out: out)
            for file in sbomFiles {
                let data = try Data(contentsOf: file)
                let json = try JSONSerialization.jsonObject(with: data)
                if file.lastPathComponent.contains("darwin") || file.lastPathComponent.contains("ios") {
                    iosDict["sbom"] = json
                } else if file.lastPathComponent.contains("android") {
                    androidDict["sbom"] = json
                }
            }
            #endif
        }

        // Extract link-type keys from platform dicts into a top-level "links" dictionary.
        let linkKeyMapping: [String: String] = [
            "privacyURL": "privacy",
            "supportURL": "support",
            "marketingURL": "marketing",
        ]

        var links: [String: Any] = [:]
        for (metaKey, linkKey) in linkKeyMapping {
            var merged: [String: String] = [:]
            if let iosLocales = iosDict.removeValue(forKey: metaKey) as? [String: String] {
                for (locale, url) in iosLocales { merged[locale] = url }
            }
            if let androidLocales = androidDict.removeValue(forKey: metaKey) as? [String: String] {
                for (locale, url) in androidLocales {
                    if merged[locale] == nil { merged[locale] = url }
                }
            }
            if !merged.isEmpty {
                links[linkKey] = collapseToDefault(merged)
            }
        }

        // Promote shared metadata fields: if a field appears in only one platform,
        // or in both platforms with identical content, move it to the app level.
        let promotableKeys = ["title", "subtitle", "description", "keywords", "releaseNotes"]
        var appDict: [String: Any] = [
            "name": productName,
        ]

        for key in promotableKeys {
            let iosVal = iosDict[key]
            let androidVal = androidDict[key]

            var promoted: Any?
            if let iosVal = iosVal, let androidVal = androidVal {
                // Both platforms have this key — promote only if identical
                if let iosData = try? JSONSerialization.data(withJSONObject: iosVal, options: .sortedKeys),
                   let androidData = try? JSONSerialization.data(withJSONObject: androidVal, options: .sortedKeys),
                   iosData == androidData {
                    promoted = iosVal
                    iosDict.removeValue(forKey: key)
                    androidDict.removeValue(forKey: key)
                }
            } else if let onlyVal = iosVal ?? androidVal {
                // Only one platform has this key — promote it
                promoted = onlyVal
                iosDict.removeValue(forKey: key)
                androidDict.removeValue(forKey: key)
            }

            // Collapse localized dictionaries when all values are identical
            if let dict = promoted as? [String: String] {
                appDict[key] = collapseToDefault(dict)
            } else if let promoted = promoted {
                appDict[key] = promoted
            }
        }

        appDict["platforms"] = [
            "ios": iosDict,
            "android": androidDict,
        ] as [String: Any]

        if !links.isEmpty {
            appDict["links"] = links
        }

        // Add source repository info from .git/config
        if let originURL = cmd.parseGitOriginURL(projectRoot: projectURL) {
            let browseURL = MetaIndexCommand.gitRemoteToHTTPS(originURL)
            var source: [String: Any] = [
                "url": originURL,
            ] as [String: Any]
            if browseURL.contains("github.com") {
                source["release"] = "\(browseURL)/releases/tag/\(version)/"
                source["assets"] = "https://raw.githubusercontent.com/\(browseURL.components(separatedBy: "github.com/").last ?? "")/refs/tags/\(version)/"
            }
            // Detect license from LICENSE file
            if let license = cmd.detectLicense(projectRoot: projectURL) {
                source["license"] = license
            }
            appDict["source"] = source
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        return [
            "$schema": "https://appfair.org/schemas/appindex/v1.json",
            "specVersion": "1.0",
            "generated": dateFormatter.string(from: Date()),
            "generator": "skip/\(skipVersion)",
            "apps": [appDict],
        ] as [String: Any]
    }

    /// Collapse a localized dictionary when all values are identical.
    /// When every locale points to the same value, returns `{ "en": value }`
    /// instead of repeating the same URL for every locale.
    private static func collapseToDefault(_ localized: [String: String]) -> [String: String] {
        let uniqueValues = Set(localized.values)
        if uniqueValues.count == 1, let value = uniqueValues.first {
            return ["en": value]
        }
        return localized
    }

    /// Write the app index JSON to a file and optionally create a symlink in the app Resources folder.
    static func writeAppIndex(_ catalog: [String: Any], to outputURL: URL, linkResource: Bool, appModuleName: String, projectURL: URL, out: MessageQueue) async throws -> URL {
        let jsonData = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try jsonData.write(to: outputURL)

        if linkResource {
            let resourcesFolder = projectURL.appendingPathComponent("Sources/\(appModuleName)/Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resourcesFolder, withIntermediateDirectories: true)

            let linkPath = resourcesFolder.appendingPathComponent(appIndexFilename).path
            try? FileManager.default.removeItem(atPath: linkPath)
            let relPath = relativePath(from: resourcesFolder.path, to: outputURL.path)
            try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: relPath)
            await out.write(status: .pass, "Linked \(appIndexFilename) -> \(relPath)")
        }

        return outputURL
    }

    // relativePath(from:to:) is defined in Utilities.swift
}

private struct AppIndexError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Android Manifest XML Parser

/// XMLParser delegate that extracts metadata and permissions from AndroidManifest.xml.
private class AndroidManifestParserDelegate: NSObject, XMLParserDelegate {
    var metadata: [String: Any] = [:]
    var permissions: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "manifest":
            if let pkg = attributeDict["package"] {
                metadata["package"] = pkg
            }
        case "application":
            if let label = attributeDict["android:label"] {
                metadata["label"] = label
            }
            if let name = attributeDict["android:name"] {
                metadata["name"] = name
            }
            if let icon = attributeDict["android:icon"] {
                metadata["icon"] = icon
            }
            if let theme = attributeDict["android:theme"] {
                metadata["theme"] = theme
            }
        case "uses-permission":
            if let name = attributeDict["android:name"] {
                permissions.append(["key": name])
            }
        case "uses-feature":
            if let name = attributeDict["android:name"] {
                var feature: [String: String] = ["name": name]
                if let required = attributeDict["android:required"] {
                    feature["required"] = required
                }
                var features = metadata["features"] as? [[String: String]] ?? []
                features.append(feature)
                metadata["features"] = features
            }
        default:
            break
        }
    }
}
