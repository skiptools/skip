import Foundation
import ArgumentParser
#if canImport(ImageIO)
import ImageIO
import struct UniformTypeIdentifiers.UTType
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct IconCommand: MessageCommand, StreamingCommand {
    static var configuration = CommandConfiguration(
        commandName: "icon",
        abstract: "Create and manage app icons",
        discussion: """
This command will create and update icons in the Darwin and Android folders of a Skip project.

Examples:

# Resize the given PNG icon for each of the required icon sizes
skip icon app_icon.png

# Resize separate icons for each of Android and iOS
skip icon --android app_icon_android.png
skip icon --darwin app_icon_darwin.png

# Generate a random icon set and open them in Preview.app
skip icon --open-preview --random-icon --random-background

# Generate new icons with a named color background
skip icon --open-preview --background skyblue

# Create new icons with a background gradient
skip icon --open-preview --background #3E8E41-#2F4F4F

# Create new icons with a background gradient overlaid with an SVG image
skip icon --open-preview --background #5C6BC0-#3B3F54 symbol.svg

# Create new icons with custom image inset and shadow radius
skip icon --background #F7DC6F-#F2C464 --inset 0.4 --shadow 0.02 symbol.svg

""",
        shouldDisplay: true)

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Root folder for icon generation", valueName: "directory"))
    var dir: String?

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Flag(help: ArgumentHelp("Open the generated icons in Preview"))
    var openPreview: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Generate an Android icon set"))
    var android: Bool? = nil

    @Option(help: ArgumentHelp("Path the Android resources root folder", valueName: "path"))
    var androidPath: String = "Android/app/src/main/res"

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Generate an Android icon set"))
    var darwin: Bool? = nil

    @Option(help: ArgumentHelp("Path the Darwin icon assets folder", valueName: "path"))
    var darwinPath: String = "Darwin/Assets.xcassets/AppIcon.appiconset"

    @Option(help: ArgumentHelp("Name or RGB hex color/gradient for icon color", valueName: "color"))
    var foreground: String = Self.defaultIconForeground
    static let defaultIconForeground: String = "white"

    @Option(help: ArgumentHelp("Name or RGB hex color/gradient for icon background", valueName: "color"))
    var background: String?

    @Option(help: ArgumentHelp("The percentage amount of inset for the shape", valueName: "amount"))
    var inset: Double = Self.defaultIconInset
    static let defaultIconInset: Double = 0.10 // 10% feels about right

    @Option(help: ArgumentHelp("The percentage amount of shadow to dear around the path", valueName: "amount"))
    var shadow: Double = Self.defaultIconShadow
    static let defaultIconShadow: Double = 0.01 // 10% feels about right

    @Flag(help: ArgumentHelp("Create a random icon shape"))
    var randomIcon: Bool = false

    @Flag(help: ArgumentHelp("Create a random icon color"))
    var randomBackground: Bool = false

    @Argument(help: "Path or URL to icon source SVG, PNG, or PDF files")
    var iconSources: [String] = []

    mutating func validate() throws {
        if iconSources.isEmpty && background == nil && randomIcon == false && randomBackground == false {
            throw ValidationError("Must specify an icon source or --background or --random-background/--random-icon")
        }
    }

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runCreateIcon(with: out)
        }
    }

    /// E.g.: for Skip Notes: `skip icon --android --darwin --open-preview --foreground white --background cyan-teal --inset 0.5 --shadow 0.01 '<svg xmlns="http://www.w3.org/2000/svg" height="24px" viewBox="0 -960 960 960" width="24px" fill="#000000"><path d="M360-200v-80h480v80H360Zm0-240v-80h480v80H360Zm0-240v-80h480v80H360ZM200-160q-33 0-56.5-23.5T120-240q0-33 23.5-56.5T200-320q33 0 56.5 23.5T280-240q0 33-23.5 56.5T200-160Zm0-240q-33 0-56.5-23.5T120-480q0-33 23.5-56.5T200-560q33 0 56.5 23.5T280-480q0 33-23.5 56.5T200-400Zm0-240q-33 0-56.5-23.5T120-720q0-33 23.5-56.5T200-800q33 0 56.5 23.5T280-720q0 33-23.5 56.5T200-640Z"/></svg>'`
    func runCreateIcon(with out: MessageQueue) async throws {
        // if neither --darwin nor --android is specified, then we generate both; otherwise, we only generate one
        let androidIcon = android == true || (darwin == nil && android == nil)
        let darwinIcon = darwin == true || (darwin == nil && android == nil)
        // when generating from a PNG, we do not create separate layers
        let separateLayers = !iconSources.contains(where: { $0.hasSuffix(".png") || $0.hasSuffix(".gif") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") })

        #if !canImport(ImageIO)
        await out.write(status: .fail, "Icon creation not supported on this platform")
        #else
        let rootDir = dir.flatMap({ URL(fileURLWithPath: $0, isDirectory: true) })
        let infos = try await generateIcons(darwinAppIconFolder: !darwinIcon ? nil : URL(fileURLWithPath: darwinPath, relativeTo: rootDir), androidAppSrcMainRes: !androidIcon ? nil : URL(fileURLWithPath: androidPath, relativeTo: rootDir), backgroundColor: background, randomBackground: randomBackground, foregroundColor: foreground, iconSources: iconSources, randomIcon: randomIcon, shadow: self.shadow, iconInset: self.inset, separateLayers: separateLayers)

        let infoURLs = infos.compactMap(\.url)
        for infoURL in infoURLs {
            await out.write(status: .pass, "Generated \(infoURL.relativeString)")
        }

        if openPreview && !infos.isEmpty {
            try await run(with: out, "Launching preview for \(infos.count) icons", ["open", "-b", "com.apple.Preview"] + infoURLs.map(\.path))
        }
        await out.write(status: .pass, "Created \(infos.count) icons")
        #endif
    }
}

struct IconParameters {
    var iconBackgroundColor: String?
    var iconForegroundColor: String?
    var iconSources: [String] = []
    var iconShadow: Double?
    var iconInset: Double?
}

struct IconInfo {
    var url: URL?
    var size: Int
    var android: Bool
    var foreground: Bool?
}

func generateIcons(darwinAppIconFolder: URL?, androidAppSrcMainRes: URL?, backgroundColor: String?, randomBackground: Bool, foregroundColor: String?, iconSources: [String], randomIcon: Bool, shadow: Double?, iconInset: Double, separateLayers: Bool) async throws -> [IconInfo] {
    /// the URL for an iOS icon
    let ios = { darwinAppIconFolder?.appendingPathComponent($0, isDirectory: false) }

    /// the URL for an Android icon
    let android = { androidAppSrcMainRes?.appendingPathComponent($0, isDirectory: false) }

    var iconInfos: [IconInfo] = [
        IconInfo(url: ios("AppIcon-20@2x.png"), size: 40, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-20@2x~ipad.png"), size: 40, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-20@3x.png"), size: 60, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-20~ipad.png"), size: 20, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-29.png"), size: 29, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-29@2x.png"), size: 58, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-29@2x~ipad.png"), size: 58, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-29@3x.png"), size: 87, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-29~ipad.png"), size: 29, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-40@2x.png"), size: 80, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-40@2x~ipad.png"), size: 80, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-40@3x.png"), size: 120, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-40~ipad.png"), size: 40, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon-83.5@2x~ipad.png"), size: 167, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon@2x.png"), size: 120, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon@2x~ipad.png"), size: 152, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon@3x.png"), size: 180, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon~ios-marketing.png"), size: 1024, android: false, foreground: nil),
        IconInfo(url: ios("AppIcon~ipad.png"), size: 76, android: false, foreground: nil),
    ]

    for (folder, size) in [
        ("mipmap-hdpi", size: 72),
        ("mipmap-mdpi", size: 48),
        ("mipmap-xhdpi", size: 96),
        ("mipmap-xxhdpi", size: 144),
        ("mipmap-xxxhdpi", size: 192),
    ] {
        iconInfos.append(IconInfo(url: android("\(folder)/ic_launcher.png"), size: size, android: true, foreground: nil))
        // Android separates layers into foreground and background in order to apply custom effects, so we additionally create foreground and background images
        if separateLayers {
            iconInfos.append(IconInfo(url: android("\(folder)/ic_launcher_background.png"), size: size, android: true, foreground: false))
            iconInfos.append(IconInfo(url: android("\(folder)/ic_launcher_foreground.png"), size: size, android: true, foreground: true))
            iconInfos.append(IconInfo(url: android("\(folder)/ic_launcher_monochrome.png"), size: size, android: true, foreground: true)) // TODO: do we need to color this differently?
        }
    }

    if let ic_launcher_xml = android("mipmap-anydpi/ic_launcher.xml") {
        // add or remove the adaptive-icons metadata file depending on whether we are using separate layers
        if separateLayers {
            // when we split between foreground and background, we also need to write out a mipmap-anydpi/ic_launcher.xml file listing the individual icons

            try """
    <?xml version="1.0" encoding="utf-8"?>
    <adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
    </adaptive-icon>
    """.write(to: ic_launcher_xml.createParentDirectory(), atomically: false, encoding: .utf8)
        } else {
            // remove the file so we do not accidentally use it
            try? FileManager.default.removeItem(at: ic_launcher_xml)
        }
    }

    let randomSource = iconSources.isEmpty && randomIcon
    let iconSources = randomSource ? [MaterialIcon.allCases.shuffled().first!.rawValue] : iconSources
    let iconBackground = backgroundColor == nil && (randomBackground || randomSource) ? randomIconColors.shuffled().first : backgroundColor

    let backgroundColors = (iconBackground ?? "").split(separator: "-").map(\.description)

    for info in iconInfos {
        if let iconFileURL = info.url {
            #if canImport(ImageIO)
            let iconImage = try await createAppIcon(width: info.size, height: info.size, circular: false, foreground: info.foreground, backgroundColors: backgroundColors, foregroundColor: foregroundColor, iconSources: iconSources, iconShadow: shadow, iconInset: iconInset)
            try iconImage.write(to: iconFileURL.createParentDirectory())
            #endif
        }
    }
    return iconInfos
}

private struct RGB {
    let red: CGFloat, green: CGFloat, blue: CGFloat

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = CGFloat(red) / 255.0
        self.green = CGFloat(green) / 255.0
        self.blue = CGFloat(blue) / 255.0
    }

    init?(colorString: String) {
        let colorNames: [String: RGB] = [
            "aliceblue": RGB(240,248,255),
            "antiquewhite": RGB(250,235,215),
            "aqua": RGB(0,255,255),
            "aquamarine": RGB(127,255,212),
            "azure": RGB(240,255,255),
            "beige": RGB(245,245,220),
            "bisque": RGB(255,228,196),
            "black": RGB(0,0,0),
            "blanchedalmond": RGB(255,235,205),
            "blue": RGB(0,0,255),
            "blueviolet": RGB(138,43,226),
            "brown": RGB(165,42,42),
            "burlywood": RGB(222,184,135),
            "cadetblue": RGB(95,158,160),
            "chartreuse": RGB(127,255,0),
            "chocolate": RGB(210,105,30),
            "coral": RGB(255,127,80),
            "cornflowerblue": RGB(100,149,237),
            "cornsilk": RGB(255,248,220),
            "crimson": RGB(220,20,60),
            "cyan": RGB(0,255,255),
            "darkblue": RGB(0,0,139),
            "darkcyan": RGB(0,139,139),
            "darkgoldenrod": RGB(184,134,11),
            "darkgray": RGB(169,169,169),
            "darkgreen": RGB(0,100,0),
            "darkgrey": RGB(169,169,169),
            "darkkhaki": RGB(189,183,107),
            "darkmagenta": RGB(139,0,139),
            "darkolivegreen": RGB(85,107,47),
            "darkorange": RGB(255,140,0),
            "darkorchid": RGB(153,50,204),
            "darkred": RGB(139,0,0),
            "darksalmon": RGB(233,150,122),
            "darkseagreen": RGB(143,188,143),
            "darkslateblue": RGB(72,61,139),
            "darkslategray": RGB(47,79,79),
            "darkslategrey": RGB(47,79,79),
            "darkturquoise": RGB(0,206,209),
            "darkviolet": RGB(148,0,211),
            "deeppink": RGB(255,20,147),
            "deepskyblue": RGB(0,191,255),
            "dimgray": RGB(105,105,105),
            "dimgrey": RGB(105,105,105),
            "dodgerblue": RGB(30,144,255),
            "firebrick": RGB(178,34,34),
            "floralwhite": RGB(255,250,240),
            "forestgreen": RGB(34,139,34),
            "fuchsia": RGB(255,0,255),
            "gainsboro": RGB(220,220,220),
            "ghostwhite": RGB(248,248,255),
            "gold": RGB(255,215,0),
            "goldenrod": RGB(218,165,32),
            "gray": RGB(128,128,128),
            "green": RGB(0,128,0),
            "greenyellow": RGB(173,255,47),
            "grey": RGB(128,128,128),
            "honeydew": RGB(240,255,240),
            "hotpink": RGB(255,105,180),
            "indianred": RGB(205,92,92),
            "indigo": RGB(75,0,130),
            "ivory": RGB(255,255,240),
            "khaki": RGB(240,230,140),
            "lavender": RGB(230,230,250),
            "lavenderblush": RGB(255,240,245),
            "lawngreen": RGB(124,252,0),
            "lemonchiffon": RGB(255,250,205),
            "lightblue": RGB(173,216,230),
            "lightcoral": RGB(240,128,128),
            "lightcyan": RGB(224,255,255),
            "lightgoldenrodyellow": RGB(250,250,210),
            "lightgray": RGB(211,211,211),
            "lightgreen": RGB(144,238,144),
            "lightgrey": RGB(211,211,211),
            "lightpink": RGB(255,182,193),
            "lightsalmon": RGB(255,160,122),
            "lightseagreen": RGB(32,178,170),
            "lightskyblue": RGB(135,206,250),
            "lightslategray": RGB(119,136,153),
            "lightslategrey": RGB(119,136,153),
            "lightsteelblue": RGB(176,196,222),
            "lightyellow": RGB(255,255,224),
            "lime": RGB(0,255,0),
            "limegreen": RGB(50,205,50),
            "linen": RGB(250,240,230),
            "magenta": RGB(255,0,255),
            "maroon": RGB(128,0,0),
            "mediumaquamarine": RGB(102,205,170),
            "mediumblue": RGB(0,0,205),
            "mediumorchid": RGB(186,85,211),
            "mediumpurple": RGB(147,112,219),
            "mediumseagreen": RGB(60,179,113),
            "mediumslateblue": RGB(123,104,238),
            "mediumspringgreen": RGB(0,250,154),
            "mediumturquoise": RGB(72,209,204),
            "mediumvioletred": RGB(199,21,133),
            "midnightblue": RGB(25,25,112),
            "mintcream": RGB(245,255,250),
            "mistyrose": RGB(255,228,225),
            "moccasin": RGB(255,228,181),
            "navajowhite": RGB(255,222,173),
            "navy": RGB(0,0,128),
            "oldlace": RGB(253,245,230),
            "olive": RGB(128,128,0),
            "olivedrab": RGB(107,142,35),
            "orange": RGB(255,165,0),
            "orangered": RGB(255,69,0),
            "orchid": RGB(218,112,214),
            "palegoldenrod": RGB(238,232,170),
            "palegreen": RGB(152,251,152),
            "paleturquoise": RGB(175,238,238),
            "palevioletred": RGB(219,112,147),
            "papayawhip": RGB(255,239,213),
            "peachpuff": RGB(255,218,185),
            "peru": RGB(205,133,63),
            "pink": RGB(255,192,203),
            "plum": RGB(221,160,221),
            "powderblue": RGB(176,224,230),
            "purple": RGB(128,0,128),
            "rebeccapurple": RGB(102, 51, 153),
            "red": RGB(255,0,0),
            "rosybrown": RGB(188,143,143),
            "royalblue": RGB(65,105,225),
            "saddlebrown": RGB(139,69,19),
            "salmon": RGB(250,128,114),
            "sandybrown": RGB(244,164,96),
            "seagreen": RGB(46,139,87),
            "seashell": RGB(255,245,238),
            "sienna": RGB(160,82,45),
            "silver": RGB(192,192,192),
            "skyblue": RGB(135,206,235),
            "slateblue": RGB(106,90,205),
            "slategray": RGB(112,128,144),
            "slategrey": RGB(112,128,144),
            "snow": RGB(255,250,250),
            "springgreen": RGB(0,255,127),
            "steelblue": RGB(70,130,180),
            "tan": RGB(210,180,140),
            "teal": RGB(0,128,128),
            "thistle": RGB(216,191,216),
            "tomato": RGB(255,99,71),
            "turquoise": RGB(64,224,208),
            "violet": RGB(238,130,238),
            "wheat": RGB(245,222,179),
            "white": RGB(255,255,255),
            "whitesmoke": RGB(245,245,245),
            "yellow": RGB(255,255,0),
            "yellowgreen": RGB(154,205,50),
        ]

        if let rgb = colorNames[colorString] {
            self = rgb
            return
        }
        var formattedHex = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        formattedHex = formattedHex.replacingOccurrences(of: "#", with: "")

        var hexValue: UInt64 = 0

        guard Scanner(string: formattedHex).scanHexInt64(&hexValue) else {
            return nil
        }

        let red = UInt8((hexValue & 0xFF0000) >> 16)
        let green = UInt8((hexValue & 0x00FF00) >> 8)
        let blue = UInt8(hexValue & 0x0000FF)

        self = RGB(red, green, blue)
    }

}

/// Subtle gradient colors with the top being lighter than the bottom
private let randomIconColors: [String] = [
    "#455A64-#2F4F7F",
    "#8B9467-#5C5C5C",
    "#4CAF50-#388E3C",
    "#7A288A-#5C3C96",
    "#2196F3-#1565C0",
    "#9C27B0-#7B1FA2",
    "#3F51B5-#303F9F",
    "#795548-#5B3F3F",
    "#009688-#00695C",
    "#4DB6AC-#388E3C",
    "#FF9800-#FF7F00",
    "#8BC34A-#5C6BC0",
    "#3E8E41-#2F4F4F",
    "#CDDC39-#8BC34A",
    "#FFC107-#FF9800",
    "#5C6BC0-#3B3F54",
    "#F57C00-#FF9800",
    "#4CAF50-#2E865F",
    "#9E9E9E-#5C5C5C",
    "#607D8B-#455A64",
    "#7BC8F6-#56B3FA",
    "#FF99CC-#FF69B4",
    "#3F51B5-#303F9F",
    "#F7DC6F-#F2C464",
    "#8B9467-#5C5C5C",
    "#2196F3-#1565C0",
    "#C5CAE9-#7A88A7",
    "#FFC0CB-#FFB6C1",
    "#4DB6AC-#388E3C",
    "#9C27B0-#7B1FA2",
    "#3E8E41-#2F4F4F",
    "#795548-#5B3F3F",
    "#FF9800-#FF7F00",
    "#8BC34A-#5C6BC0",
    "#CDDC39-#8BC34A",
    "#F57C00-#FF9800",
    "#5C6BC0-#3B3F54",
    "#4CAF50-#2E865F",
    "#9E9E9E-#5C5C5C",
    "#607D8B-#455A64",
    "#7BC8F6-#56B3FA",
    "#FF99CC-#FF69B4",
    "#3F51B5-#303F9F",
    "#F7DC6F-#F2C464",
    "#8B9467-#5C5C5C",
    "#2196F3-#1565C0",
    "#C5CAE9-#7A88A7",
    "#FFC0CB-#FFB6C1",
    "#4DB6AC-#388E3C",
    "#9C27B0-#7B1FA2",
]

public struct IconCommandError : LocalizedError {
    public var errorDescription: String?
}

#if canImport(ImageIO)

/// Creates a rectangular PNG filled with the specified
func createAppIcon(width: Int, height: Int, circular: Bool, foreground: Bool?, backgroundColors: [String], foregroundColor: String?, iconSources: [String], iconShadow: Double?, iconInset: Double, alpha: Double = 1.0) async throws -> Data {
    let size = CGSize(width: width, height: height)
    let rect = CGRect(origin: CGPointZero, size: size)

    let rgbs = try backgroundColors.map { colorString in
        guard let rgb = RGB(colorString: colorString) else {
            throw IconCommandError(errorDescription: "Could not parse icon color: \(colorString)")
        }
        return rgb
    }

    let bytesPerPixel = 4
    let bitsPerComponent = 8
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerPixel * width, space: colorSpace, bitmapInfo: bitmapInfo) else {
        throw IconCommandError(errorDescription: "Could not create icon context")
    }

    // TODO: gradient
    //context.setFillColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    //context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Define the start and end points for the gradient

    let colors = rgbs.map({ CGColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: alpha) })

    if circular {
        context.addEllipse(in: rect)
    } else {
        context.addRect(rect)
    }
    context.clip()
    let startPoint = CGPoint(x: rect.midX, y: rect.maxY)
    let endPoint = CGPoint(x: rect.midX, y: rect.minY)
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0]) {
        if foreground != true {
            context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        }
    }
    if let shadow = iconShadow {
        context.setShadow(
            offset: CGSize(width: 0, height: -1 * CGFloat(height) / 75.0),
            blur: CGFloat(height) * shadow,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        )
    }

    var inset = CGFloat(height) * iconInset

    // when split into foreground and background layers, additional insets are needed to account for the safe area and not overlap the background
    // https://developer.android.com/develop/ui/views/launch/icon_design_adaptive
    if foreground == true {
        inset += CGFloat(height) * 0.60
    }

    context.translateBy(x: inset / 4.0, y: inset / 4.0)
    let iconSize = CGSize(width: CGFloat(width) - (inset / 2.0), height: CGFloat(height) - (inset / 2.0))

    if let foregroundColor = foregroundColor, let foregroundColorRGB = RGB(colorString: foregroundColor) {
        //context.setBlendMode(.sourceIn) // This blend mode replaces the existing color with the new color
        context.setStrokeColor(red: foregroundColorRGB.red, green: foregroundColorRGB.green, blue: foregroundColorRGB.blue, alpha: alpha)
        context.setFillColor(red: foregroundColorRGB.red, green: foregroundColorRGB.green, blue: foregroundColorRGB.blue, alpha: alpha)
    }

    /// Fetch the URL at the given string
    func fetch(_ path: String) async throws -> Data {
        if path.hasPrefix("http"), let pathURL = URL(string: path) {
            let (data, response) = try await URLSession.shared.data(from: pathURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) {
                throw IconCommandError(errorDescription: "Download icon url \(path) failed: \(code)")
            }
            return data
        } else {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
    }

    for iconSource in iconSources {
        let svgFile = iconSource.hasSuffix(".svg")
        if svgFile || iconSource.hasPrefix("<svg") {
            if foreground != false {
                // raw SVG String
                let svgData = svgFile ? try await fetch(iconSource) : iconSource.utf8Data
                var svgString = String(data: svgData, encoding: .utf8) ?? ""
                if let foregroundColor = foregroundColor {
                    // also update and individual fill data for any individual paths
                    let svgString2 = svgString.replacing(try Regex("fill=\"([^\"]+)\""), with: { match in
                        "fill=\"\(foregroundColor)\""
                    })
                    if svgString2 != svgString {
                        // don't replace twice, otherwise: "Entity: line 1: parser error : Attribute fill redefined"
                        svgString = svgString2
                    } else {
                        // set the global fill color in the SVG (since setting the context's foreground and fill colors don't seem to work)
                        svgString = svgString.replacing(try Regex("<svg "), with: { match in
                            "<svg fill=\"\(foregroundColor)\" "
                        })
                    }
                }
                guard let svg = SVG(svgString) else {
                    throw IconCommandError(errorDescription: "Could not load SVG image from: \(iconSource)")
                }
                svg.draw(in: context, size: iconSize)
            }
        } else { // non-SVG images are written to the background
            // the icon is drawn to the background, since it is not an overlay image
            if foreground != true {
                // try to load the image
                let pngData = try await fetch(iconSource)
                guard let imageSource: CGImageSource = CGImageSourceCreateWithData(pngData as CFData, nil) else {
                    throw IconCommandError(errorDescription: "Could not load image data from \(iconSource)")
                }
                guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    throw IconCommandError(errorDescription: "Could not create image from \(iconSource)")
                }

                context.center(size: size, target: size, flip: false)
                context.draw(cgImage, in: rect)
            }
        }
    }

    guard let cgImage = context.makeImage() else {
        throw IconCommandError(errorDescription: "Could not create icon image")
    }

    let pngData = NSMutableData()
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0] // Set compression quality to 1.0 (highest)
    guard let destination = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, options as CFDictionary) else {
        throw IconCommandError(errorDescription: "Could not create icon destination")
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)

    return pngData as Data
}

extension CGContext {
    /// Applies a transform to center the `target` size in the canvas `size`, optionally flipping the contents.
    func center(size: CGSize, target: CGSize, flip: Bool) {
        let context = self
        var target = target

        let ratio = (x: target.width / size.width, y: target.height / size.height)
        let rect = (document: CGRect(origin: .zero, size: size), ())
        let scale: (x: CGFloat, y: CGFloat)

        if target.width <= 0 {
            scale = (ratio.y, ratio.y)
            target.width = size.width * scale.x
        } else if target.height <= 0 {
            scale = (ratio.x, ratio.x)
            target.width = size.width * scale.y
        } else {
            let min = min(ratio.x, ratio.y)
            scale = (min, min)
            target.width = size.width * scale.x
            target.height = size.height * scale.y
        }

        let transform = (
            scale: CGAffineTransform(scaleX: scale.x, y: scale.y),
            aspect: CGAffineTransform(translationX: (target.width / scale.x - rect.document.width) / 2, y: (target.height / scale.y - rect.document.height) / 2)
        )

        if flip {
            context.translateBy(x: 0, y: target.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.concatenate(transform.scale)
        context.concatenate(transform.aspect)
    }
}

@objc
class CGSVGDocument: NSObject { }

private var CGSVGDocumentRetain: (@convention(c) (CGSVGDocument?) -> Unmanaged<CGSVGDocument>?) = loadFunction("CGSVGDocumentRetain")
private var CGSVGDocumentRelease: (@convention(c) (CGSVGDocument?) -> Void) = loadFunction("CGSVGDocumentRelease")
private var CGSVGDocumentCreateFromData: (@convention(c) (CFData?, CFDictionary?) -> Unmanaged<CGSVGDocument>?) = loadFunction("CGSVGDocumentCreateFromData")
private var CGContextDrawSVGDocument: (@convention(c) (CGContext?, CGSVGDocument?) -> Void) = loadFunction("CGContextDrawSVGDocument")
private var CGSVGDocumentGetCanvasSize: (@convention(c) (CGSVGDocument?) -> CGSize) = loadFunction("CGSVGDocumentGetCanvasSize")

private let CoreSVG = dlopen("/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_NOW)

private func loadFunction<T>(_ name: String) -> T {
    unsafeBitCast(dlsym(CoreSVG, name), to: T.self)
}

class SVG {
    deinit { CGSVGDocumentRelease(document) }

    let document: CGSVGDocument

    convenience init?(_ value: String) {
        guard let data = value.data(using: .utf8) else { return nil }
        self.init(data)
    }

    init?(_ data: Data) {
        guard let document = CGSVGDocumentCreateFromData(data as CFData, nil)?.takeUnretainedValue() else { return nil }
        guard CGSVGDocumentGetCanvasSize(document) != .zero else { return nil }
        self.document = document
    }

    var size: CGSize {
        CGSVGDocumentGetCanvasSize(document)
    }

    func draw(in context: CGContext) {
        draw(in: context, size: size)
    }

    func draw(in context: CGContext, size target: CGSize, flip: Bool = false) {
        context.center(size: size, target: target, flip: flip)
        CGContextDrawSVGDocument(context, document)
    }
}

//private typealias ImageWithCGSVGDocument = @convention(c) (AnyObject, Selector, CGSVGDocument) -> NSImage
//private var ImageWithCGSVGDocumentSEL: Selector = NSSelectorFromString("_imageWithCGSVGDocument:")
//extension SVG {
//    func image() -> NSImage? {
//        let ImageWithCGSVGDocument = unsafeBitCast(NSImage.self.method(for: ImageWithCGSVGDocumentSEL), to: ImageWithCGSVGDocument.self)
//        let image = ImageWithCGSVGDocument(NSImage.self, ImageWithCGSVGDocumentSEL, document)
//        return image
//    }
//}

#endif

/// A sampling of some material icons to create random images
///
/// Generated by checking out https://github.com/google/material-design-icons and running:
///
/// ```
/// for file in $(ls ./symbols/web/*/materialsymbolsrounded/*_wght300_40px.svg | egrep '/rocket_wght|/egg_wght/|/cyclone_wght|/favorite_wght|/star_half_wg|/dataset_wg|/open_with_wg|/select_all_wght|/view_cozy_wg|/deployed_code_w|/stacks_wg|/stack_star_wg|/dialogs_wg|/tile_large_wg|/thumb_up_wg|/person_wg|/sentiment_satisfied_wg|/rocket_launch_wg|/pets_wg|/mood_wg|/diamond_wg|/clear_day_wg|/crowdsource_wg|/chess_wg|/folded_hands_wg|/owl_wg|/local_florist_wg'); do echo "    case icon_$(basename ${file} _wght300_40px.svg) = \"\"\""; cat ${file}; echo ""; echo "\"\"\""; echo ""; done | pbcopy
/// ```
enum MaterialIcon : String, CaseIterable {

    case icon_chess = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M205.64-165.64h548.72v-86.03q0-5.38-3.46-8.84-3.47-3.47-8.85-3.47h-524.1q-5.38 0-8.85 3.47-3.46 3.46-3.46 8.84v86.03Zm119.69-148.59h309.34l-25.72-180.64h-257.9l-25.72 180.64ZM186.54-115.39q-13.26 0-22.21-8.99-8.94-8.99-8.94-22.29v-105q0-25.61 18.47-44.08 18.48-18.48 44.09-18.48h57.13l25.77-180.64h-75.46q-10.68 0-17.91-7.27-7.22-7.26-7.22-17.99 0-10.74 7.22-17.87 7.23-7.13 17.91-7.13h509.22q10.68 0 17.91 7.27 7.22 7.26 7.22 17.99 0 10.74-7.22 17.87-7.23 7.13-17.91 7.13h-75.46l25.77 180.64h57.04q25.79 0 44.22 18.48 18.43 18.47 18.43 44.08v105q0 13.3-8.97 22.29-8.97 8.99-22.23 8.99H186.54ZM480.1-835.2q5.15 0 10.22 1.72 5.06 1.71 9.65 5.15 22.85 16.82 48.48 25.59 25.63 8.77 53.78 8.77 19.54 0 38.42-4.61 18.89-4.6 37.71-14.19 7.69-3.56 14.74-3.27 7.05.3 12.54 4.63 5.49 4.33 8.46 10.75 2.97 6.42 1.23 13.69l-53.95 241.84h-51.87l45.72-205.95q-13.62 3.41-27.71 5.59-14.09 2.18-29.39 2.18-31.91 0-61.75-8.74T480-777.72q-26.33 16.93-56.22 25.67-29.88 8.74-61.73 8.74-15.33 0-29.31-1.92-13.97-1.92-27.33-5.08l45.08 205.18h-51.87l-53.31-241.84q-2-7.74.97-13.71 2.98-5.96 8.54-10.35 5.56-4.4 12.45-5.16 6.89-.76 14.42 3.68 18 8.92 37.17 13.73 19.17 4.81 38.53 4.81 28.53 0 54.16-8.77 25.63-8.77 48.48-25.59 4.59-3.44 9.75-5.15 5.16-1.72 10.32-1.72Zm-.1 340.33Zm.38-50.26ZM480-165.64Z"/></svg>
"""

    case icon_clear_day = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M479.87-756.41q-10.74 0-17.87-7.22-7.13-7.23-7.13-17.91v-92.56q0-10.68 7.27-17.91 7.26-7.22 17.99-7.22 10.74 0 17.87 7.22 7.13 7.23 7.13 17.91v92.56q0 10.68-7.27 17.91-7.26 7.22-17.99 7.22Zm195.36 81.18q-7.23-7.23-7.04-17.41.19-10.18 7.42-17.97L740-776.38q7.62-7.82 18.09-7.82 10.47 0 18.38 7.9 7.53 7.53 7.53 17.61 0 10.07-7.62 17.69l-65.77 65.77q-7.61 7.61-17.69 7.61-10.07 0-17.69-7.61Zm106.31 220.36q-10.68 0-17.91-7.27-7.22-7.26-7.22-17.99 0-10.74 7.22-17.87 7.23-7.13 17.91-7.13h92.56q10.68 0 17.91 7.27 7.22 7.26 7.22 17.99 0 10.74-7.22 17.87-7.23 7.13-17.91 7.13h-92.56ZM479.87-60.77q-10.74 0-17.87-7.22-7.13-7.23-7.13-17.91v-92.18q0-10.68 7.27-17.9 7.26-7.23 17.99-7.23 10.74 0 17.87 7.23 7.13 7.22 7.13 17.9v92.18q0 10.68-7.27 17.91-7.26 7.22-17.99 7.22Zm-230.1-614.46L183.62-740q-7.82-7.5-7.82-18.14 0-10.63 7.97-18.24 7.46-7.23 17.79-7.23 10.34 0 17.44 7.23l66.15 66.15q7.23 7.1 7.23 17.44 0 10.33-7.15 17.56-7.72 6.82-18.01 6.82-10.3 0-17.45-6.82Zm491.28 491.61-65.44-65.77q-7.23-7.79-7.42-17.97-.19-10.18 6.96-17.41 6.91-6.82 17.28-6.82 10.36 0 18.18 7.2l66.18 64.77q7.44 7.24 7.2 17.73-.25 10.5-7.24 18.34-7.38 7.75-17.99 7.75t-17.71-7.82ZM85.9-454.87q-10.68 0-17.91-7.27-7.22-7.26-7.22-17.99 0-10.74 7.22-17.87 7.23-7.13 17.91-7.13h92.56q10.68 0 17.91 7.27 7.22 7.26 7.22 17.99 0 10.74-7.22 17.87-7.23 7.13-17.91 7.13H85.9Zm98.1 271.1q-7.23-7.46-7.42-17.73-.19-10.27 7.04-17.5L249-284.39q7.37-7.2 17.47-7.2 10.09 0 17.92 7.28 7.82 7.94 7.82 18.21 0 10.28-7.82 18.1L220-183.62q-7.82 7.82-18.36 7.82T184-183.77ZM480.09-260q-91.63 0-155.86-64.14Q260-388.28 260-479.91q0-91.63 64.14-155.86Q388.28-700 479.91-700q91.63 0 155.86 64.14Q700-571.72 700-480.09q0 91.63-64.14 155.86Q571.72-260 480.09-260Zm-.13-50.26q70.5 0 120.14-49.6t49.64-120.1q0-70.5-49.6-120.14t-120.1-49.64q-70.5 0-120.14 49.6t-49.64 120.1q0 70.5 49.6 120.14t120.1 49.64ZM480-480Z"/></svg>
"""

    case icon_crowdsource = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M646.15-563.08q-23.74 0-39.56-15.82-15.82-15.82-15.82-39.56 0-23.74 15.82-39.56 15.82-15.82 39.56-15.82 23.75 0 39.57 15.82t15.82 39.56q0 23.74-15.82 39.56-15.82 15.82-39.57 15.82Zm-332.3 0q-23.75 0-39.57-15.82t-15.82-39.56q0-23.74 15.82-39.56 15.82-15.82 39.57-15.82 23.74 0 39.56 15.82 15.82 15.82 15.82 39.56 0 23.74-15.82 39.56-15.82 15.82-39.56 15.82ZM480-461.54q-23.74 0-39.56-15.82-15.82-15.82-15.82-39.56 0-23.75 15.82-39.57T480-572.31q23.74 0 39.56 15.82 15.82 15.82 15.82 39.57 0 23.74-15.82 39.56-15.82 15.82-39.56 15.82Zm0-203.07q-23.74 0-39.56-15.82-15.82-15.83-15.82-39.57 0-23.74 15.82-39.56 15.82-15.82 39.56-15.82 23.74 0 39.56 15.82 15.82 15.82 15.82 39.56 0 23.74-15.82 39.57-15.82 15.82-39.56 15.82Zm.02 479.99q-18.07 0-36.7-2.74-18.63-2.74-36.09-7.49V-327.1q0-32.7 20.82-55.87 20.82-23.18 51.95-23.18 31.13 0 51.95 23.18 20.82 23.17 20.82 55.87v132.25q-17.46 4.75-36.07 7.49t-36.68 2.74ZM351.85-213.9q-17.97-7.34-35.31-16.52-17.33-9.17-32.91-20.31-26.09-17.89-41.24-47.55-15.16-29.67-15.16-63.31 0-23.75-4.91-44.83-4.91-21.09-18.2-39.67-9.61-11.83-35.09-36.14-25.49-24.3-46.7-45.57-10.97-11.4-10.97-26.34 0-14.93 11.05-25.81 11.64-11.72 25.98-11.72 14.33 0 25.71 11.64l141.83 133.78q17.79 16.61 26.85 39.45 9.07 22.85 9.07 46.8v146.1Zm256.3 0v-145.94q0-24.21 10.52-47.11 10.51-22.9 27.97-39.15l139.51-133.92q11.09-10.16 26.34-10.16t25.48 10.23q11.05 11.05 11.05 26 0 14.94-10.95 26.23-21.17 21.05-46.85 44.82-25.68 23.78-35.38 36.8-13.33 18.42-18.2 39.56-4.87 21.14-4.87 45.09 0 33.58-15.03 63.31-15.02 29.73-41.38 47.82-15.18 10.32-32.64 19.7-17.46 9.38-35.57 16.72Z"/></svg>
"""

    case icon_cyclone = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480-344.87q-55.77 0-95.45-39.68T344.87-480q0-56.18 39.68-95.65 39.68-39.48 95.45-39.48 56.18 0 95.65 39.48 39.48 39.47 39.48 95.65 0 55.77-39.48 95.45-39.47 39.68-95.65 39.68Zm0-50.26q35.56 0 60.22-24.99 24.65-24.98 24.65-59.88 0-35.56-24.65-60.22-24.66-24.65-60.22-24.65-34.9 0-59.88 24.65-24.99 24.66-24.99 60.22 0 34.9 24.99 59.88 24.98 24.99 59.88 24.99Zm0 216.21q-129.39 0-211.65-11.17-82.27-11.17-140.94-26.86-12.41-3.44-21.06-12.59-8.66-9.15-8.66-21.97 0-10.26 8.94-15.98 8.93-5.71 19.99-2.54 48.69 13.65 94.16 20.9 45.48 7.26 80.53 9.72-54.9-37.54-88.64-103.68-33.75-66.14-33.75-136.91 0-106.56 11.68-196.65t26.73-156.32q3.18-12.41 12.08-20.88 8.9-8.46 21.72-8.46 10.25 0 16.36 8.94 6.1 8.93 2.92 19.99-12.69 51.89-19.55 95.42-6.86 43.53-10.63 78.45 40.18-56.05 104.59-88.81 64.41-32.76 135.18-32.76 117.85 0 203.38 11.3 85.54 11.29 148.82 26.73 12.41 3.18 21.26 12.27 8.85 9.09 8.85 21.91 0 10.25-8.94 16.16-8.93 5.91-19.99 2.74-48.82-12.7-94.84-20.34-46.03-7.64-78.65-10.25 59.06 43.28 90.12 107.88 31.07 64.6 31.07 132.68 0 122.85-11.75 207.87-11.74 85.03-26.66 144.72-3.18 12.41-12.27 21.06-9.09 8.66-21.91 8.66-10.26 0-16.37-8.75-6.12-8.74-2.94-19.79 12.87-48.05 20.45-93.25 7.58-45.19 10.55-80.24-42.95 58.18-106.95 89.49-64 31.31-133.23 31.31Zm0-50.26q104.21 0 177.51-73.31 73.31-73.3 73.31-177.51t-73.31-177.51q-73.3-73.31-177.51-73.31t-177.51 73.31q-73.31 73.3-73.31 177.51t73.31 177.51q73.3 73.31 177.51 73.31Z"/></svg>
"""

    case icon_dataset = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M326.15-294.87h67.7q12.89 0 22.08-9.2 9.2-9.19 9.2-22.08v-67.7q0-12.89-9.2-22.08-9.19-9.2-22.08-9.2h-67.7q-12.89 0-22.08 9.2-9.2 9.19-9.2 22.08v67.7q0 12.89 9.2 22.08 9.19 9.2 22.08 9.2Zm240 0h67.7q12.89 0 22.08-9.2 9.2-9.19 9.2-22.08v-67.7q0-12.89-9.2-22.08-9.19-9.2-22.08-9.2h-67.7q-12.89 0-22.08 9.2-9.2 9.19-9.2 22.08v67.7q0 12.89 9.2 22.08 9.19 9.2 22.08 9.2Zm-240-240h67.7q13.39 0 22.33-8.95 8.95-8.94 8.95-22.33v-67.7q0-13.39-8.95-22.33-8.94-8.95-22.33-8.95h-67.7q-13.39 0-22.33 8.95-8.95 8.94-8.95 22.33v67.7q0 13.39 8.95 22.33 8.94 8.95 22.33 8.95Zm240 0h67.7q13.39 0 22.33-8.95 8.95-8.94 8.95-22.33v-67.7q0-13.39-8.95-22.33-8.94-8.95-22.33-8.95h-67.7q-13.39 0-22.33 8.95-8.95 8.94-8.95 22.33v67.7q0 13.39 8.95 22.33 8.94 8.95 22.33 8.95ZM202.56-140q-25.78 0-44.17-18.39T140-202.56v-554.88q0-25.78 18.39-44.17T202.56-820h554.88q25.78 0 44.17 18.39T820-757.44v554.88q0 25.78-18.39 44.17T757.44-140H202.56Zm0-50.26h554.88q4.61 0 8.46-3.84 3.84-3.85 3.84-8.46v-554.88q0-4.61-3.84-8.46-3.85-3.84-8.46-3.84H202.56q-4.61 0-8.46 3.84-3.84 3.85-3.84 8.46v554.88q0 4.61 3.84 8.46 3.85 3.84 8.46 3.84Zm-12.3-579.48v579.48-579.48Z"/></svg>
"""

    case icon_deployed_code = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M454.87-163.03v-302.71L190.26-618.77v295.8q0 3.07 1.53 5.76 1.54 2.7 4.62 4.62l258.46 149.56Zm50.26 0 258.46-149.56q3.08-1.92 4.62-4.62 1.53-2.69 1.53-5.76v-296.21L505.13-465.85v302.82ZM480-508.51 741.21-660.2 486.15-807.77q-3.07-1.67-6.15-1.67-3.08 0-6.15 1.67L218.38-660.2 480-508.51ZM171.28-268.82q-14.93-8.64-23.11-23.07-8.17-14.42-8.17-31.14v-313.94q0-16.72 8.17-31.14 8.18-14.43 23.11-23.07L448.72-851.2q14.99-8.36 31.39-8.36t31.17 8.36l277.44 160.02q14.93 8.64 23.11 23.07 8.17 14.42 8.17 31.14v313.94q0 16.72-8.17 31.14-8.18 14.43-23.11 23.07L511.28-108.8q-14.99 8.36-31.39 8.36t-31.17-8.36L171.28-268.82ZM480-480Z"/></svg>
"""

    case icon_dialogs = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M343.95-312.67h272.1q13.14 0 22.21-9.07t9.07-22.21v-272.1q0-13.14-9.07-22.21t-22.21-9.07h-272.1q-13.14 0-22.21 9.07t-9.07 22.21v272.1q0 13.14 9.07 22.21t22.21 9.07ZM202.56-140q-25.78 0-44.17-18.39T140-202.56v-554.88q0-25.78 18.39-44.17T202.56-820h554.88q25.78 0 44.17 18.39T820-757.44v554.88q0 25.78-18.39 44.17T757.44-140H202.56Zm0-50.26h554.88q4.61 0 8.46-3.84 3.84-3.85 3.84-8.46v-554.88q0-4.61-3.84-8.46-3.85-3.84-8.46-3.84H202.56q-4.61 0-8.46 3.84-3.84 3.85-3.84 8.46v554.88q0 4.61 3.84 8.46 3.85 3.84 8.46 3.84Zm-12.3-579.48v579.48-579.48Z"/></svg>
"""

    case icon_diamond = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480-171.26q-13.31 0-25.87-5.38-12.57-5.39-21.92-16.49L118.05-570.26q-7.41-8.36-10.99-18.32-3.57-9.96-3.57-21.32 0-7.15 1.9-14.14 1.89-6.99 5.3-13.93l77.95-157.54q8.1-15.77 23.17-25.13 15.06-9.36 32.78-9.36h470.82q17.72 0 32.78 9.36 15.07 9.36 23.42 25.13l77.95 157.54q3.16 6.94 5.05 13.93 1.9 6.99 1.9 14.14 0 11.36-3.57 21.32-3.58 9.96-10.99 18.32l-313.9 377.13q-9.61 11.1-22.18 16.49-12.56 5.38-25.87 5.38ZM360.59-625.13h238.82l-77.18-154.61h-84.46l-77.18 154.61Zm94.28 381.21v-330.95H179.92l274.95 330.95Zm50.26 0 275.2-330.95h-275.2v330.95Zm150.41-381.21h142.92l-73.97-147.69q-1.54-3.08-4.62-5-3.07-1.92-6.54-1.92H578.1l77.44 154.61Zm-493.75 0h142.93l77.18-154.61H246.67q-3.47 0-6.54 1.92-3.08 1.92-4.62 5l-73.72 147.69Z"/></svg>
"""

    case icon_favorite = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M479.62-168.23q-11.23 0-22.52-4.06t-19.86-12.69l-49.5-45.23q-115.3-105.66-201.52-203.7Q100-531.95 100-638.46q0-83.25 56.14-139.39Q212.28-834 295.13-834q47.31 0 95.99 23.26 48.67 23.25 88.88 81.67 42.51-58.42 89.71-81.67Q616.9-834 664.87-834q82.85 0 138.99 56.15Q860-721.71 860-638.46q0 107.66-87.98 206.45-87.97 98.78-200.1 201.75l-49.7 45.44q-8.48 8.54-19.82 12.56-11.35 4.03-22.78 4.03Zm-22.44-506.85q-31.64-53.51-72.94-81.09-41.29-27.57-89.11-27.57-62.98 0-103.92 41.15-40.95 41.15-40.95 104.34 0 50.92 31.9 105.99 31.91 55.08 80.16 109.34 48.24 54.25 104.63 105.61 56.38 51.36 104.97 95.54 3.46 3.33 8.08 3.33t8.08-3.33q48.59-43.77 104.97-95.33 56.39-51.57 104.55-106.13 48.17-54.57 80.16-109.65 31.98-55.08 31.98-105.5 0-63.06-41.17-104.21-41.17-41.15-103.77-41.15-48.42 0-89.38 27.37Q534.46-729 502-675.08q-4.26 6.62-10.05 9.85-5.8 3.23-12.49 3.23t-12.69-3.23q-6-3.23-9.59-9.85ZM480-500.64Z"/></svg>
"""

    case icon_folded_hands = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M671.69-449.03v93.9q0 10.87-7.13 18-7.13 7.13-18 7.13-10.87 0-18-7.13-7.12-7.13-7.12-18V-436l-46.13-85.08q-19.21 1.98-31.93 16.59-12.71 14.62-12.71 33.98v218.56l69.23 114.13q7.82 12.69.39 25.25Q592.87-100 578.2-100q-6.82 0-12.56-3.1-5.74-3.11-9.18-8.98l-76.05-125.61v-232.82q0-33.28 19.36-59.64t50.64-36.16l-65.87-122.15q-18.46-35.05-16.13-73.89 2.33-38.83 29.62-66.11l32.2-32.39q9.56-9.56 23.72-9.25 14.15.31 22.51 11.25l230.82 272.36q6.15 7.77 10.17 16.43 4.01 8.65 5.01 18.62l35.77 424.08q.95 11.28-6.47 19.32-7.43 8.04-18.71 8.04-9.87 0-16.9-6.72-7.02-6.72-8.23-16.59l-36.77-428.72-219.38-259.18-17.75 18.13q-14.2 14.21-16.89 33.66-2.7 19.45 6.46 36.83l148.1 273.56Zm-382.97 0 148.1-273.56q9.41-17.38 6.59-36.83-2.82-19.45-17.02-33.66l-17.49-18.13-219.64 259.18-36.77 428.67q-1.21 10.13-8.23 16.74-7.03 6.62-16.9 6.62-11.28 0-18.7-8.04-7.43-8.04-6.22-19.32l35.79-424.08q1-9.97 4.68-18.62 3.68-8.66 10.09-16.43l230.95-272.36q8.61-10.94 22.55-11.25 13.94-.31 23.5 9.25l32.38 32.39q27.29 27.28 29.62 66.11 2.33 38.84-16.13 73.89l-66.26 122.15q31.29 9.8 50.84 36.16Q480-503.79 480-470.51v232.82l-76.05 125.61q-3.44 5.87-9.15 8.98-5.72 3.1-12.54 3.1-14.26 0-21.58-12.57-7.32-12.56.5-25.25l68.57-114.13v-218.56q0-19.36-12.72-33.98-12.72-14.61-31.93-16.59L338.97-436v80.87q0 10.87-7.12 18-7.13 7.13-18 7.13-10.87 0-18-7.13-7.13-7.13-7.13-18v-93.9Z"/></svg>
"""

    case icon_local_florist = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480-103.67q0-111.43 79.13-205.87 79.13-94.43 187.72-116.15 12.84-2.77 24.87-.73 12.02 2.04 20.38 11.86 8.87 9.61 10.58 21.72 1.7 12.11-1.07 24.17Q777.9-260.8 683.93-182.23 589.97-103.67 480-103.67Zm60.61-60.02q78.75-23.57 132.13-76.82 53.39-53.26 76.95-132.26-79 23.56-132.26 77.15-53.25 53.59-76.82 131.93ZM480-103.08q0-111.43-79.13-205.87-79.13-94.43-187.72-116.15-12.84-2.77-24.87-.73-12.02 2.04-20.38 11.6-8.87 9.87-10.58 22.19-1.7 12.31 1.07 24.37Q182.1-259.8 276.07-181.44q93.96 78.36 203.93 78.36Zm-60.61-60.61q-78.75-23.57-132.13-76.82-53.39-53.26-76.7-132.26 78.75 23.56 132.01 77.15 53.25 53.59 76.82 131.93Zm121.22 0Zm-121.22 0Zm60.82-432.08q20.23 0 34.56-14.54 14.33-14.54 14.33-34.77 0-20.23-14.24-34.56-14.25-14.33-34.86-14.33-20.03 0-34.56 14.24-14.54 14.25-14.54 34.86 0 20.02 14.54 34.56 14.53 14.54 34.77 14.54Zm-.12 197.95q-33.77 0-61.04-19.96-27.28-19.97-38.97-53.43-5.67 1.16-11.78 1.66-6.12.5-11.91.5-43.33 0-74.15-30.56-30.83-30.56-30.83-73.99 0-19.02 7.6-37.02 7.61-18 21.12-34.25-12.9-16.26-20.31-34.26-7.41-18-7.41-36.72 0-43.81 30.48-74.32 30.48-30.52 73.5-30.52 5.69 0 12.03.5 6.35.5 12.04 1.27 11.69-33.08 38.69-53.04 26.99-19.96 60.85-19.96t60.85 19.96q27 19.96 38.69 53.04 5.69-.77 12.04-1.27 6.34-.5 12.03-.5 43.02 0 73.5 30.56 30.48 30.56 30.48 73.99 0 19.15-7.1 37.27-7.11 18.13-20.62 34 12.9 16.25 20.31 34.25 7.41 18 7.41 36.72 0 43.82-30.48 74.33-30.48 30.52-73.5 30.52-5.69 0-12.03-.5-6.35-.5-12.43-1.66-11.3 33.46-38.3 53.43-26.99 19.96-60.76 19.96Zm123.66-121.49q22.22 0 38.21-15.97 15.99-15.97 15.99-38.44 0-16.56-9.18-29.54-9.18-12.97-24.64-18.54l-44.93-16.12q-1.74 11.72-5.23 22.33-3.48 10.62-8.79 20.13-5.31 9.51-12.39 17.74-7.07 8.23-16.56 14.87l35.2 30.5q6.34 6.32 14.38 9.68 8.04 3.36 17.94 3.36ZM579.2-652.08l44.93-15.87q15.45-5.56 24.33-18.96 8.87-13.4 8.87-29.24 0-22.28-15.53-38.28-15.54-16.01-38.24-16.01-9.59 0-17.49 3.36-7.91 3.36-14.89 9.57L535.2-726.9q9.23 6.64 16.65 14.69 7.41 8.04 12.69 17.34 5.95 9.43 9.46 20.13 3.51 10.69 5.2 22.66Zm-141.3-82.64q11.25-4.43 21.77-6.97 10.51-2.54 20.39-2.54 9.89 0 20.4 2.54 10.51 2.54 21.64 6.97l11.85-55.67q4.31-20.81-13.04-36.04-17.35-15.24-40.7-15.24-23.36 0-40.92 15.34-17.55 15.34-13.24 35.94l11.85 55.67Zm42.31 286.64q23.35 0 40.7-15.23 17.35-15.24 13.04-36.05l-11.85-55.67q-11.13 4.82-21.64 7.17-10.51 2.35-20.4 2.35-9.88 0-20.46-2.35-10.57-2.35-21.7-7.17l-11.85 55.67q-4.31 20.61 13.24 35.95 17.56 15.33 40.92 15.33Zm-99.41-204q1.69-11.97 5.2-22.66 3.51-10.7 8.82-20.03 5.31-9.34 12.52-17.41 7.2-8.08 16.43-14.72l-35.2-30.49q-6.34-6.33-14.38-9.69-8.04-3.36-17.94-3.36-22.22 0-38.21 15.98-15.99 15.97-15.99 38.44 0 15.98 9.18 29.24 9.18 13.26 24.64 18.83l44.93 15.87Zm-24.53 132.16q9.56 0 17.52-3.26 7.95-3.26 15.03-9.67l35.98-30q-9.23-6.64-16.65-14.71-7.41-8.07-12.82-17.54-5.41-9.46-9.06-20.41-3.65-10.95-5.47-22.41l-44.93 16.12q-15.45 5.57-24.52 18.98-9.07 13.42-9.07 29.26.62 22.61 15.91 38.12 15.29 15.52 38.08 15.52Zm208.81-75.62Zm-.41-99.33ZM480-744.23Zm0 198.72Zm-85.08-149.36Zm.41 99.74Z"/></svg>
"""

    case icon_mood = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M619.22-534.05q20.42 0 34.83-14.5 14.41-14.5 14.41-34.93 0-20.42-14.5-34.83-14.5-14.41-34.92-14.41t-34.83 14.5q-14.41 14.5-14.41 34.93 0 20.42 14.5 34.83 14.5 14.41 34.92 14.41Zm-278.26 0q20.42 0 34.83-14.5 14.41-14.5 14.41-34.93 0-20.42-14.5-34.83-14.5-14.41-34.92-14.41t-34.83 14.5q-14.41 14.5-14.41 34.93 0 20.42 14.5 34.83 14.5 14.41 34.92 14.41ZM480.07-100q-78.84 0-148.21-29.92t-120.68-81.21q-51.31-51.29-81.25-120.63Q100-401.1 100-479.93q0-78.84 29.92-148.21t81.21-120.68q51.29-51.31 120.63-81.25Q401.1-860 479.93-860q78.84 0 148.21 29.92t120.68 81.21q51.31 51.29 81.25 120.63Q860-558.9 860-480.07q0 78.84-29.92 148.21t-81.21 120.68q-51.29 51.31-120.63 81.25Q558.9-100 480.07-100ZM480-480Zm-.02 329.74q138.06 0 233.91-95.82 95.85-95.83 95.85-233.9 0-138.06-95.82-233.91-95.83-95.85-233.9-95.85-138.06 0-233.91 95.82-95.85 95.83-95.85 233.9 0 138.06 95.82 233.91 95.83 95.85 233.9 95.85Zm-.37-122.46q53.58 0 98.84-24.51 45.26-24.51 73.72-67.73 5.93-10.66-.2-21.16-6.12-10.5-18.38-10.5H326.36q-12.54 0-18.5 10.5-5.96 10.5-.03 21.16 28.43 43.22 73.78 67.73 45.34 24.51 98 24.51Z"/></svg>
"""

    case icon_open_with = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M454.87-191.79v-166.72q0-10.7 7.25-17.92 7.25-7.21 18-7.21t17.88 7.21q7.13 7.22 7.13 17.92V-192l72.72-72.92q7.52-7.44 18.16-7.5 10.63-.07 18.45 7.69 7.82 7.77 7.82 18.17 0 10.41-7.82 18.25l-112.6 112.6q-4.89 4.89-10.29 6.99-5.41 2.1-11.69 2.1-6.29 0-11.57-2.1t-10.18-7l-112.8-112.79q-7.43-7.44-7.52-18.02-.09-10.57 7.73-18.26 7.82-7.7 18.11-7.7t18.3 7.57l72.92 73.13ZM192-454.87l70.36 70.41q7.43 7.54 7.63 18.17.19 10.62-7.7 18.19-7.63 7.82-18.18 7.82T226-348.1l-110.24-110q-4.94-4.93-7.04-10.33-2.1-5.41-2.1-11.69 0-6.29 2.1-11.57t7.02-10.21l110.67-110.66q7.66-7.44 18.12-7.5 10.47-.07 18.29 7.62 7.82 7.7 7.82 18.1 0 10.4-7.82 18.19l-71.03 71.02h166.72q10.7 0 17.92 7.25 7.21 7.25 7.21 18T376.43-462q-7.22 7.13-17.92 7.13H192Zm576.21 0H601.9q-10.7 0-17.92-7.25-7.21-7.25-7.21-18t7.21-17.88q7.22-7.13 17.92-7.13H768l-70.36-70.41q-7.43-7.54-7.63-18.17-.19-10.62 7.7-18.44 7.63-7.57 18.13-7.57 10.51 0 18.42 7.57l110 110.24q4.92 4.94 7.15 10.34 2.23 5.41 2.23 11.69 0 6.29-2.23 11.57t-7.17 10.22L734.05-347.9q-7.43 7.44-18.04 7.53-10.6.09-18.42-7.73-7.56-7.57-7.56-17.95 0-10.39 7.56-18.46l70.62-70.36ZM454.87-768.21l-70.56 70.57q-7.42 7.43-18.03 7.63-10.61.19-18.18-7.63-7.82-7.57-7.82-17.95 0-10.38 7.82-18.46l110-110.19q4.93-4.94 10.33-7.17 5.41-2.23 11.69-2.23 6.29 0 11.57 2.23t10.22 7.17L612.1-734.05q7.44 7.41 7.63 18.03.19 10.61-7.63 18.43-7.56 7.56-17.95 7.56-10.38 0-18.46-7.56l-70.56-70.62v166.31q0 10.7-7.25 17.92-7.25 7.21-18 7.21T462-583.98q-7.13-7.22-7.13-17.92v-166.31Z"/></svg>
"""

    case icon_owl = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480-100q-125.13 0-212.56-87.81Q180-275.61 180-401.23v-196.8q0-114.04 89.85-188Q359.69-860 480-860q117.61 0 208.81 73Q780-713.99 780-598.03v447q0 21.09-14.97 36.06Q750.06-100 728.97-100H480Zm0-50.26h117.67q-33.82-27.3-53.44-67.43-19.61-40.13-19.61-87.44v-34.49q-11.16 1.8-22.12 2.29-10.96.48-22.37.48-72.85 0-138.04-30.13-65.19-30.12-110.35-86.15l-1.48 51.9q0 104.23 72.65 177.6 72.65 73.37 177.09 73.37Zm94.87-154.87q0 64 45.44 109.44 45.43 45.43 109.43 45.43l-1.48-302.49q-29.96 37.62-68.77 63.05-38.8 25.42-84.62 39.01v45.56Zm-94.83-81.97q99.26 0 174.48-58.54 75.22-58.54 75.22-152.39 0-39.12-14.22-72.51-14.23-33.38-39.7-59.64-70.43 2.45-120.56 51.52-50.13 49.06-50.13 119.89 0 10.7-7.25 17.91-7.25 7.22-18 7.22T462-540.86q-7.13-7.21-7.13-17.91 0-71.38-50.5-120.34-50.5-48.97-121.24-50.48-24.97 26.22-38.92 59.57-13.95 33.34-13.95 71.99 0 93.85 75.26 152.39 75.26 58.54 174.52 58.54ZM342.45-568.28q-12.55 0-21.03-8.6-8.47-8.59-8.47-21.26 0-12.42 8.59-21.03 8.6-8.6 21.27-8.6 12.42 0 21.02 8.72 8.61 8.72 8.61 21.27 0 12.55-8.72 21.02-8.72 8.48-21.27 8.48Zm274.87 0q-12.55 0-21.03-8.6-8.47-8.59-8.47-21.26 0-12.42 8.59-21.03 8.6-8.6 21.27-8.6 12.42 0 21.02 8.72 8.61 8.72 8.61 21.27 0 12.55-8.72 21.02-8.72 8.48-21.27 8.48ZM335.43-770.23q47.65 12.08 85.36 41.77 37.72 29.69 59.21 70.87 21.23-41.59 58.71-70.88 37.47-29.3 84.86-41.76-31.34-18.97-67.73-29.24t-75.85-10.27q-39.46 0-76.37 10.27-36.9 10.27-68.19 29.24ZM780-150.26H524.62 780Zm-300 0q-104.44 0-177.09-73.37t-72.65-177.6h1.48q-1.07 104.56 71.53 177.77 72.61 73.2 176.73 73.2h117.67H480Zm94.87-154.87q0 64 45.1 109.44 45.11 45.43 108.29 45.43h1.48q-64 0-109.43-45.43-45.44-45.44-45.44-109.44Zm-95.28-352.46Z"/></svg>
"""

    case icon_person = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480-492.72q-57.75 0-96.44-38.69t-38.69-96.56q0-57.88 38.69-96.44 38.69-38.56 96.44-38.56t96.44 38.56q38.69 38.56 38.69 96.44 0 57.87-38.69 96.56-38.69 38.69-96.44 38.69Zm-300 254v-29.23q0-31.28 16.71-55.58 16.7-24.29 43.8-37.34 61.88-28.41 121.06-42.74 59.18-14.34 118.42-14.34t118.23 14.54q58.98 14.54 120.69 42.72 27.81 13.03 44.45 37.24Q780-299.23 780-267.95v29.23q0 21.09-14.97 36.06-14.97 14.97-36.06 14.97H231.03q-21.09 0-36.06-14.97Q180-217.63 180-238.72Zm50.26.77h499.48v-30q0-14.46-8.93-27.45-8.94-12.99-23.58-20.6-56.56-27.62-109.34-39.65-52.78-12.04-107.89-12.04t-108.43 12.04Q318.26-343.62 262.36-316q-14.64 7.61-23.37 20.6-8.73 12.99-8.73 27.45v30ZM480-542.97q35.97 0 60.42-24.45 24.45-24.45 24.45-60.43 0-35.97-24.45-60.42-24.45-24.45-60.42-24.45t-60.42 24.45q-24.45 24.45-24.45 60.42 0 35.98 24.45 60.43 24.45 24.45 60.42 24.45Zm0-84.88Zm0 389.9Z"/></svg>
"""

    case icon_pets = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M175.05-489.87q-35.79 0-60.42-24.71Q90-539.29 90-575.08t24.71-60.42q24.71-24.63 60.5-24.63t60.42 24.71q24.63 24.71 24.63 60.5t-24.72 60.42q-24.71 24.63-60.49 24.63Zm182.44-164.87q-35.67 0-60.3-24.72-24.63-24.71-24.63-60.49 0-35.79 24.71-60.42Q321.98-825 357.76-825q35.55 0 60.3 24.71 24.76 24.71 24.76 60.5t-24.83 60.42q-24.83 24.63-60.5 24.63Zm244.87 0q-35.67 0-60.3-24.72-24.62-24.71-24.62-60.49 0-35.79 24.7-60.42Q566.85-825 602.64-825q35.54 0 60.3 24.71 24.75 24.71 24.75 60.5t-24.83 60.42q-24.83 24.63-60.5 24.63Zm182.43 164.87q-35.79 0-60.42-24.71-24.63-24.71-24.63-60.5t24.72-60.42q24.71-24.63 60.49-24.63 35.79 0 60.42 24.71Q870-610.71 870-574.92t-24.71 60.42q-24.71 24.63-60.5 24.63ZM266-85q-39.67 0-65.4-30.08-25.73-30.07-25.73-71.05 0-45.43 30.18-79.22 30.18-33.78 60.8-66.83 25.61-26.92 45.86-57.28 20.24-30.36 42.91-59.64 24.23-33 54.68-59.58t70.7-26.58q40.68 0 71.7 26.31 31.02 26.31 54.86 60.1 22.72 29.03 42.54 59.41 19.82 30.39 45.05 57.26 30.62 33.05 60.8 66.83 30.18 33.79 30.18 79.22 0 40.98-25.73 71.05Q733.67-85 694-85q-54 0-107-9t-107-9q-54 0-107 9t-107 9Z"/></svg>
"""

    case icon_rocket = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M342.77-223.36q-13.03-38.46-22.45-78.12-9.42-39.65-14.86-80.03l-59.43 39.64q-2.7 1.92-4.04 4.42-1.35 2.5-1.35 5.58v145.41q0 1.92 1.35 2.69 1.34.77 2.88 0l97.9-39.59Zm128.2-559.36q-64.3 72.13-92.51 151.23-28.2 79.11-28.2 178.28 0 53.57 11.53 111.61 11.54 58.04 31.44 111.34h173.54q19.9-53.3 31.44-111.34 11.53-58.04 11.53-111.61 0-99.17-28.2-178.28-28.21-79.1-92.51-151.23-2.06-2.2-4.21-3.31-2.15-1.1-4.89-1.1-2.75 0-4.85 1.1-2.09 1.11-4.11 3.31Zm8.97 327.85q-27.2 0-46.13-19-18.94-18.99-18.94-46.19t19-46.13q18.99-18.94 46.19-18.94t46.13 19q18.94 18.99 18.94 46.19t-19 46.13q-18.99 18.94-46.19 18.94Zm137.29 231.9 97.9 39.59q1.54.76 2.88-.2 1.35-.96 1.35-2.88v-145.03q0-3.08-1.35-5.77-1.34-2.69-4.04-4.61l-59.43-39.64q-5.44 40.38-14.86 80.23-9.42 39.84-22.45 78.31ZM502.69-839.28q80.72 78.67 119.01 174.43Q660-569.08 660-450.77q0 3.13.19 5.96.19 2.84-.19 6.35l81.15 55.02q13.14 8.39 20.8 22.34 7.66 13.94 7.66 29.2v177.77q0 16.68-13.73 26.08-13.73 9.41-29.5 3.25L590.2-180H369.41l-136.18 54.82q-15.77 6.15-29.3-3.25-13.54-9.4-13.54-26.08v-177.77q0-15.27 7.46-29.21 7.47-13.94 20.61-22.33L300-438.85v-11.92q0-118.31 38.3-214.08 38.29-95.76 119.01-174.43 4.77-4.74 10.82-6.95 6.05-2.2 12.04-2.2 5.98 0 11.87 2.2 5.88 2.21 10.65 6.95Z"/></svg>
"""

    case icon_rocket_launch = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M295.87-486q18.46-36.41 39.57-71.1 21.1-34.69 45.64-67.13l-69.67-14.08q-3.08-.77-5.96.19-2.89.97-5.19 3.27L197.41-532.26q-1.15 1.16-.77 2.83.39 1.66 1.92 2.17L295.87-486Zm486.18-304.92q-96.59 5.79-172.76 41.96-76.16 36.17-145.98 105.99-37.87 37.87-70.87 86.82-33 48.95-56.31 101.07l122.69 122.75q52.13-23.57 101.27-56.57 49.14-33 87.01-70.87 69.82-69.82 105.99-145.49 36.17-75.66 41.96-172.25 0-2.57-.72-5.19-.72-2.63-2.66-4.84-1.95-1.95-4.38-2.66-2.42-.72-5.24-.72ZM556.87-552.54q-18.82-18.56-18.82-45.74 0-27.18 18.82-46t46.1-18.82q27.29 0 46.11 18.82t18.82 46q0 27.18-18.82 45.74-18.82 18.82-46.11 18.82-27.28 0-46.1-18.82Zm-67.13 261 41.26 97.1q.51 1.54 2.18 1.73 1.67.2 2.82-.96l102.59-102.2q2.31-2.31 3.27-5.32.96-3.02.19-5.84l-13.67-69.92q-32.43 24.54-67.2 45.87-34.77 21.34-71.44 39.54Zm355.28-516.82q1.21 112.18-39.32 207.22-40.52 95.04-124.47 179.24-2.33 2.08-4.6 4.08-2.27 2-4.61 4.08l19.29 96.46q3.2 15.77-1.4 30.41t-15.71 25.74L548.33-135q-11.82 11.56-28.13 8.46-16.3-3.1-22.46-18.87L439.9-280.18l-155.57-156.1-135.17-57.44q-15.77-6.41-18.45-22.92-2.68-16.51 8.88-28.08l125.46-125.71q11.11-11.11 25.98-15.72 14.87-4.62 30.38-1.41l96.46 19.28q2.08-2.08 4.09-4.08 2.02-2 4.35-4.07 83.95-84.21 178.78-124.93 94.83-40.71 207.01-39.25 6.41-.05 12.3 2.46 5.88 2.51 10.83 7.46 4.95 5.2 7.27 10.56 2.32 5.36 2.52 11.77ZM177.05-319.05q29.23-29.49 71.14-29.6 41.91-.12 71.4 29.37 29.23 29.23 28.92 71.14-.31 41.91-29.54 71.39-40.28 40.03-95.58 49.17-55.31 9.14-111.31 15.83 6.69-56.38 15.69-111.83 9-55.45 49.28-95.47Zm35.34 36.18q-20.77 21.59-27.67 50.59-6.9 29-11.59 59.25 30.26-4.69 59.13-11.8 28.87-7.12 50.72-27.89 15.79-14.31 16-35.24.2-20.94-14.77-36.32-15.39-14.98-36.32-14.68-20.94.29-35.5 16.09Z"/></svg>
"""

    case icon_select_all = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M167.32-765.13q-11.72 0-19.52-7.92-7.8-7.92-7.8-19.63 0-11.72 7.92-19.52 7.93-7.8 19.64-7.8t19.51 7.92q7.8 7.93 7.8 19.64t-7.92 19.51q-7.92 7.8-19.63 7.8Zm156.41 0q-11.97 0-19.65-7.92-7.67-7.92-7.67-19.63 0-11.72 7.79-19.52 7.79-7.8 19.64-7.8 11.84 0 19.64 7.92 7.8 7.93 7.8 19.64t-7.92 19.51q-7.92 7.8-19.63 7.8Zm156.15 0q-11.71 0-19.51-7.92-7.81-7.92-7.81-19.63 0-11.72 7.93-19.52 7.92-7.8 19.63-7.8 11.71 0 19.51 7.92 7.81 7.93 7.81 19.64t-7.93 19.51q-7.92 7.8-19.63 7.8Zm156.41 0q-11.97 0-19.64-7.92-7.68-7.92-7.68-19.63 0-11.72 7.79-19.52 7.79-7.8 19.64-7.8 11.84 0 19.64 7.92 7.81 7.93 7.81 19.64t-7.93 19.51q-7.92 7.8-19.63 7.8Zm156.15 0q-11.71 0-19.51-7.92-7.8-7.92-7.8-19.63 0-11.72 7.92-19.52 7.92-7.8 19.63-7.8 11.72 0 19.52 7.92 7.8 7.93 7.8 19.64t-7.92 19.51q-7.93 7.8-19.64 7.8ZM167.32-608.97q-11.72 0-19.52-7.79-7.8-7.79-7.8-19.64 0-11.84 7.92-19.64 7.93-7.81 19.64-7.81t19.51 7.93q7.8 7.92 7.8 19.63 0 11.97-7.92 19.64-7.92 7.68-19.63 7.68Zm625.12 0q-11.71 0-19.51-7.79-7.8-7.79-7.8-19.64 0-11.84 7.92-19.64 7.92-7.81 19.63-7.81 11.72 0 19.52 7.93 7.8 7.92 7.8 19.63 0 11.97-7.92 19.64-7.93 7.68-19.64 7.68ZM167.32-452.56q-11.72 0-19.52-7.93-7.8-7.92-7.8-19.63 0-11.71 7.92-19.51 7.93-7.81 19.64-7.81t19.51 7.93q7.8 7.92 7.8 19.63 0 11.71-7.92 19.51-7.92 7.81-19.63 7.81Zm625.12 0q-11.71 0-19.51-7.93-7.8-7.92-7.8-19.63 0-11.71 7.92-19.51 7.92-7.81 19.63-7.81 11.72 0 19.52 7.93 7.8 7.92 7.8 19.63 0 11.71-7.92 19.51-7.93 7.81-19.64 7.81ZM167.32-296.41q-11.72 0-19.52-7.79-7.8-7.79-7.8-19.64 0-11.84 7.92-19.64 7.93-7.8 19.64-7.8t19.51 7.92q7.8 7.92 7.8 19.63 0 11.97-7.92 19.65-7.92 7.67-19.63 7.67Zm625.12 0q-11.71 0-19.51-7.79-7.8-7.79-7.8-19.64 0-11.84 7.92-19.64 7.92-7.8 19.63-7.8 11.72 0 19.52 7.92 7.8 7.92 7.8 19.63 0 11.97-7.92 19.65-7.93 7.67-19.64 7.67ZM167.32-140q-11.72 0-19.52-7.92-7.8-7.93-7.8-19.64t7.92-19.51q7.93-7.8 19.64-7.8t19.51 7.92q7.8 7.92 7.8 19.63 0 11.72-7.92 19.52-7.92 7.8-19.63 7.8Zm156.41 0q-11.97 0-19.65-7.92-7.67-7.93-7.67-19.64t7.79-19.51q7.79-7.8 19.64-7.8 11.84 0 19.64 7.92 7.8 7.92 7.8 19.63 0 11.72-7.92 19.52-7.92 7.8-19.63 7.8Zm156.15 0q-11.71 0-19.51-7.92-7.81-7.93-7.81-19.64t7.93-19.51q7.92-7.8 19.63-7.8 11.71 0 19.51 7.92 7.81 7.92 7.81 19.63 0 11.72-7.93 19.52-7.92 7.8-19.63 7.8Zm156.41 0q-11.97 0-19.64-7.92-7.68-7.93-7.68-19.64t7.79-19.51q7.79-7.8 19.64-7.8 11.84 0 19.64 7.92 7.81 7.92 7.81 19.63 0 11.72-7.93 19.52-7.92 7.8-19.63 7.8Zm156.15 0q-11.71 0-19.51-7.92-7.8-7.93-7.8-19.64t7.92-19.51q7.92-7.8 19.63-7.8 11.72 0 19.52 7.92 7.8 7.92 7.8 19.63 0 11.72-7.92 19.52-7.93 7.8-19.64 7.8ZM358.97-296.41q-25.8 0-44.18-18.38t-18.38-44.18v-242.31q0-25.61 18.38-44.09 18.38-18.48 44.18-18.48h242.31q25.61 0 44.09 18.48 18.48 18.48 18.48 44.09v242.31q0 25.8-18.48 44.18t-44.09 18.38H358.97Zm0-50.26h242.31q5.13 0 8.72-3.46 3.59-3.46 3.59-8.84v-242.31q0-5.13-3.59-8.72-3.59-3.59-8.72-3.59H358.97q-5.38 0-8.84 3.59t-3.46 8.72v242.31q0 5.38 3.46 8.84t8.84 3.46Z"/></svg>
"""

    case icon_sentiment_satisfied = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480.17-272.72q51.81 0 98.24-24.08 46.44-24.07 74.28-67.76 7.21-10.44 1.25-21.25-5.95-10.81-17.84-10.81-5.95 0-10.37 2.74-4.42 2.73-8.06 7.39-23.41 33.77-59.58 52.57-36.17 18.79-77.71 18.79-41.15 0-77.69-18.25-36.54-18.26-59.95-52.7-3.18-4.66-7.88-7.6-4.71-2.94-10.5-2.94-11.78 0-17.38 10.85-5.59 10.85 1.61 22.28 28.43 43.73 73.91 67.25 45.48 23.52 97.67 23.52Zm139.05-261.33q20.42 0 34.83-14.5 14.41-14.5 14.41-34.93 0-20.42-14.5-34.83-14.5-14.41-34.92-14.41t-34.83 14.5q-14.41 14.5-14.41 34.93 0 20.42 14.5 34.83 14.5 14.41 34.92 14.41Zm-278.26 0q20.42 0 34.83-14.5 14.41-14.5 14.41-34.93 0-20.42-14.5-34.83-14.5-14.41-34.92-14.41t-34.83 14.5q-14.41 14.5-14.41 34.93 0 20.42 14.5 34.83 14.5 14.41 34.92 14.41ZM480.07-100q-78.84 0-148.21-29.92t-120.68-81.21q-51.31-51.29-81.25-120.63Q100-401.1 100-479.93q0-78.84 29.92-148.21t81.21-120.68q51.29-51.31 120.63-81.25Q401.1-860 479.93-860q78.84 0 148.21 29.92t120.68 81.21q51.31 51.29 81.25 120.63Q860-558.9 860-480.07q0 78.84-29.92 148.21t-81.21 120.68q-51.29 51.31-120.63 81.25Q558.9-100 480.07-100ZM480-480Zm-.02 329.74q138.06 0 233.91-95.82 95.85-95.83 95.85-233.9 0-138.06-95.82-233.91-95.83-95.85-233.9-95.85-138.06 0-233.91 95.82-95.85 95.83-95.85 233.9 0 138.06 95.82 233.91 95.83 95.85 233.9 95.85Z"/></svg>
"""

    case icon_stack_star = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="m600-294.82 62.2 37.69q4.95 2.41 9.07-.59 4.11-3 2.91-8.15l-16.41-71.01 54.38-47.25q3.95-3.15 2.27-7.96-1.68-4.81-7.09-5.55l-71.46-6.23-28.69-67.64q-1.69-5-6.98-5-5.29 0-7.35 4.95l-28.72 67.69-71.46 6.23q-5.41.74-7.09 5.55-1.68 4.81 2.27 7.96l54.64 47.21-16.67 71.05q-1.2 5.15 2.91 8.15 4.12 3 9.07.59l62.2-37.69ZM162.56-340q-25.7 0-44.13-18.43Q100-376.86 100-402.56v-394.88q0-25.7 18.43-44.13Q136.86-860 162.56-860h394.88q25.7 0 44.13 18.43Q620-823.14 620-797.44v74.36q0 10.7-7.25 17.92-7.25 7.21-18 7.21t-17.88-7.21q-7.13-7.22-7.13-17.92v-74.36q0-5.38-3.46-8.84t-8.84-3.46H162.56q-5.38 0-8.84 3.46t-3.46 8.84v394.88q0 5.38 3.46 8.84t8.84 3.46h74.36q10.7 0 17.92 7.25 7.21 7.25 7.21 18t-7.21 17.88q-7.22 7.13-17.92 7.13h-74.36Zm240 240q-25.7 0-44.13-18.43Q340-136.86 340-162.56v-394.88q0-25.7 18.43-44.13Q376.86-620 402.56-620h394.88q25.7 0 44.13 18.43Q860-583.14 860-557.44v394.88q0 25.7-18.43 44.13Q823.14-100 797.44-100H402.56Zm0-50.26h394.88q5.38 0 8.84-3.46t3.46-8.84v-394.88q0-5.38-3.46-8.84t-8.84-3.46H402.56q-5.38 0-8.84 3.46t-3.46 8.84v394.88q0 5.38 3.46 8.84t8.84 3.46ZM600-360Z"/></svg>
"""

    case icon_stacks = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480-425.15q-7.77 0-14.76-1.9-6.98-1.9-14.14-5.46L113-611q-8.61-4.95-12.38-12.03-3.77-7.07-3.77-15.69 0-8.36 3.77-15.43 3.77-7.08 12.38-12.03l338.1-178.49q7.16-3.56 14.14-5.46 6.99-1.89 14.76-1.89t14.76 1.89q6.98 1.9 14.14 5.46l338.48 178.49q8.62 4.95 12.59 12.03 3.98 7.07 3.98 15.43 0 8.62-3.98 15.69-3.97 7.08-12.59 12.03L508.9-432.51q-7.16 3.56-14.14 5.46-6.99 1.9-14.76 1.9Zm0-49.52 315.49-164.05L480-802.51 165.56-638.72 480-474.67Zm.79-164.05ZM480-315.79l332.46-174.34q2.39-1.13 13.75-1.61 9.43.77 15.93 7.51t6.5 16.85q0 6.82-3.11 12.23-3.12 5.41-9.94 9.46L508.9-274.05q-7.16 3.82-14.14 5.59-6.99 1.77-14.76 1.77t-14.76-1.77q-6.98-1.77-14.14-5.59L125.46-445.69q-6.82-4.05-10.25-9.46-3.44-5.41-3.44-12.23 0-10.11 6.69-16.85 6.69-6.74 16.13-7.51 3.82-.77 7.2-.25 3.39.53 6.8 2.53L480-315.79Zm0 158.71 332.46-174.33q2.39-1.38 13.75-1.87 9.43 1.02 15.93 7.77 6.5 6.74 6.5 16.59 0 6.82-3.11 12.36-3.12 5.53-9.94 9.58L508.9-115.33q-7.16 3.82-14.14 5.59-6.99 1.76-14.76 1.76t-14.76-1.76q-6.98-1.77-14.14-5.59L125.46-286.98q-6.82-4.05-10.25-9.58-3.44-5.54-3.44-12.36 0-9.85 6.69-16.59 6.69-6.75 16.13-7.77 3.82-.51 7.2.01 3.39.53 6.8 2.27L480-157.08Z"/></svg>
"""

    case icon_star_half = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M480-699.77v348.41l141.03 85.92-37.21-160.77 124.13-107.64-163.59-14.48L480-699.77Zm0 407.31-165.36 99.79q-7.2 4-14.57 3.53-7.38-.48-13.38-4.73-6-4.26-9.1-11.17-3.1-6.91-.9-15.35l43.62-187.92-145.64-126.77q-6.62-5.61-8.32-12.93-1.71-7.32.7-14.4 2.16-6.82 7.7-11.35 5.53-4.52 14.17-5.47l192.54-16.92 74.85-177.67q3.43-7.56 9.96-11.41 6.53-3.84 13.73-3.84t13.73 3.84q6.53 3.85 9.96 11.41l74.85 177.67 192.54 16.92q8.64.95 14.17 5.47 5.54 4.53 7.95 11.35 2.16 7.08.45 14.4-1.7 7.32-8.32 12.93L639.69-408.31l43.87 187.92q1.95 8.44-1.15 15.35-3.1 6.91-9.1 11.17-6 4.25-13.38 4.73-7.37.47-14.57-3.53L480-292.46Z"/></svg>
"""

    case icon_thumb_up = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M835.13-616.2q24.64 0 43.6 18.96t18.96 43.6v65.6q0 6.39-.05 13.38-.05 6.99-2.46 13.22L777.83-187.13q-8.61 19.8-28.86 33.46Q728.71-140 707.19-140H284.67v-476.2l225.25-230.7q10.99-11.25 25.92-13.56 14.93-2.31 28.39 5.26 13.31 7.56 19.79 21.51 6.49 13.95 2.98 29.1L546.97-616.2h288.16Zm-500.21 21.33v404.61h378.77q3.98 0 8.53-2.3 4.55-2.31 6.86-7.7l118.36-279.33v-74.05q0-5.13-3.59-8.72-3.59-3.59-8.72-3.59H484.92l49.49-233.18-199.49 204.26ZM162.15-140q-25.8 0-44.18-18.48t-18.38-44.08v-351.08q0-25.61 18.38-44.09 18.38-18.47 44.18-18.47h122.52v50.25H162.15q-5.38 0-8.84 3.59t-3.46 8.72v351.08q0 5.38 3.46 8.84t8.84 3.46h122.52V-140H162.15Zm172.77-50.26v-404.61 404.61Z"/></svg>
"""

    case icon_tile_large = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M140-171.28v-149.01q0-12.99 9.24-22.18 9.25-9.2 22.04-9.2h227.26q13.06 0 22.17 9.25 9.11 9.24 9.11 22.04v149q0 13.49-8.99 22.43-9 8.95-22.29 8.95H171.28q-13.29 0-22.29-8.99-8.99-9-8.99-22.29Zm389.82 0v-149.01q0-13.24 8.99-22.31 9-9.07 22.29-9.07h227.62q13.29 0 22.29 9.12 8.99 9.12 8.99 22.17v149q0 13.49-8.99 22.43-9 8.95-22.29 8.95H561.1q-13.29 0-22.29-8.99-8.99-9-8.99-22.29ZM140-482.69v-306.03q0-13.29 8.99-22.29 9-8.99 22.29-8.99h617.44q13.29 0 22.29 8.99 8.99 9 8.99 22.29v306.03q0 13.29-8.99 22.29-9 8.99-22.29 8.99H171.28q-13.29 0-22.29-8.99-8.99-9-8.99-22.29Zm50.26 292.43h189.31v-111.15H190.26v111.15Zm389.82 0h189.66v-111.15H580.08v111.15ZM285.1-246.23Zm390.21 0Z"/></svg>
"""

    case icon_view_cozy = """
<svg xmlns="http://www.w3.org/2000/svg" height="40" viewBox="0 -960 960 960" width="40"><path d="M357.44-540H202.56q-25.78 0-44.17-18.39T140-602.56v-154.88q0-25.78 18.39-44.17T202.56-820h154.88q25.78 0 44.17 18.39T420-757.44v154.88q0 25.78-18.39 44.17T357.44-540Zm-154.88-50.25h154.88q5.38 0 8.84-3.47 3.47-3.46 3.47-8.84v-154.88q0-5.38-3.47-8.84-3.46-3.46-8.84-3.46H202.56q-5.38 0-8.84 3.46t-3.46 8.84v154.88q0 5.38 3.46 8.84 3.46 3.47 8.84 3.47ZM357.44-140H202.56q-25.78 0-44.17-18.39T140-202.56v-154.88q0-25.78 18.39-44.17T202.56-420h154.88q25.78 0 44.17 18.39T420-357.44v154.88q0 25.78-18.39 44.17T357.44-140Zm-154.88-50.26h154.88q5.38 0 8.84-3.46 3.47-3.46 3.47-8.84v-154.88q0-5.38-3.47-8.84-3.46-3.47-8.84-3.47H202.56q-5.38 0-8.84 3.47-3.46 3.46-3.46 8.84v154.88q0 5.38 3.46 8.84t8.84 3.46ZM757.44-540H602.56q-25.78 0-44.17-18.39T540-602.56v-154.88q0-25.78 18.39-44.17T602.56-820h154.88q25.78 0 44.17 18.39T820-757.44v154.88q0 25.78-18.39 44.17T757.44-540Zm-154.88-50.25h154.88q5.38 0 8.84-3.47 3.46-3.46 3.46-8.84v-154.88q0-5.38-3.46-8.84t-8.84-3.46H602.56q-5.38 0-8.84 3.46-3.47 3.46-3.47 8.84v154.88q0 5.38 3.47 8.84 3.46 3.47 8.84 3.47ZM757.44-140H602.56q-25.78 0-44.17-18.39T540-202.56v-154.88q0-25.78 18.39-44.17T602.56-420h154.88q25.78 0 44.17 18.39T820-357.44v154.88q0 25.78-18.39 44.17T757.44-140Zm-154.88-50.26h154.88q5.38 0 8.84-3.46t3.46-8.84v-154.88q0-5.38-3.46-8.84-3.46-3.47-8.84-3.47H602.56q-5.38 0-8.84 3.47-3.47 3.46-3.47 8.84v154.88q0 5.38 3.47 8.84 3.46 3.46 8.84 3.46ZM369.75-590.25Zm0 220.5Zm220.5-220.5Zm0 220.5Z"/></svg>
"""


}
