#if !SKIP
@_exported import CrossFoundation
import SwiftUI

public typealias App = SwiftUI.App
public typealias Scene = SwiftUI.Scene
public typealias WindowGroup = SwiftUI.WindowGroup

public typealias View = SwiftUI.View
public typealias State = SwiftUI.State
public typealias Binding = SwiftUI.Binding
public typealias ObservableObject = SwiftUI.ObservableObject
public typealias EnvironmentObject = SwiftUI.EnvironmentObject

//public typealias ForEach = SwiftUI.ForEach

public typealias HStack = SwiftUI.HStack
public typealias VStack = SwiftUI.VStack

//public typealias Rectangle = SwiftUI.Rectangle

public typealias Text = SwiftUI.Text
public typealias Label = SwiftUI.Label
public typealias Color = SwiftUI.Color
public typealias Button = SwiftUI.Button
public typealias TabView = SwiftUI.TabView
public typealias TextField = SwiftUI.TextField

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public typealias NavigationLink = SwiftUI.NavigationLink

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public typealias NavigationStack = SwiftUI.NavigationStack


public typealias Published = SwiftUI.Published
public typealias StateObject = SwiftUI.StateObject

#endif

internal func CrossUIInternalModuleName() -> String {
    return "CrossUI"
}

public func CrossUIPublicModuleName() -> String {
    return "CrossUI"
}
