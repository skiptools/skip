#if !SKIP
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

public typealias Text = SwiftUI.Text
public typealias HStack = SwiftUI.HStack
public typealias VStack = SwiftUI.VStack
//public typealias Rectangle = SwiftUI.Rectangle

public typealias Button = SwiftUI.Button

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public typealias NavigationLink = SwiftUI.NavigationLink


#endif

internal func SkipUIInternalModuleName() -> String {
    return "SkipUI"
}

public func SkipUIPublicModuleName() -> String {
    return "SkipUI"
}
