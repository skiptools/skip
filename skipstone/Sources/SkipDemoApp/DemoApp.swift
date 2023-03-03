#if !SKIP
import SkipUI
import SkipFoundation
import SwiftUI

public let logger: Logger = Logger(subsystem: "activity", category: "DemoApp")

//class DemoApp : ComponentActivity() {
//    override fun onCreate(savedInstanceState: Bundle?) {
//        super.onCreate(savedInstanceState)
//        setContent {
//            SwiftUIComposeTheme {
//                Surface(color = MaterialTheme.colors.background) {
//                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
//                        RootView().Compose(ComposeContext())
//                    }
//                }
//            }
//        }
//    }
//}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public struct SkipDemoApp : App {
    public init() {
    }

    public var body: some Scene {
        WindowGroup {
            RootView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

struct ButtonView : View {
    let title: String
    let onClick: () -> ()

    init(_ title: String = "Tap me", onClick: @escaping () -> ()) {
        self.title = title
        self.onClick = onClick
    }

    var body: some View {
        Button {
            onClick()
        } label: {
            Text(title)
        }
        .buttonStyle(.borderedProminent)
    }
}

struct TextFieldView : View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
    }

}

struct TextView : View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
    }
}

//class RootView: View() {
//    fun body(): View {
//        return TabView { listOf(
//            ContentView(),
//            DestinationTwo(),
//            ContentView(),
//        )}
//    }
//
//    // Synthesize
//    @Composable
//    override fun Compose(context: ComposeContext) {
//        body().Compose(context)
//    }
//}


@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct RootView : View {
    var body: some View {
        TabView {
            ContentView().tabItem({ Label("ONE", systemImage: "1.circle") })
            DestinationTwo().tabItem({ Label("TWO", systemImage: "2.circle") })
            ContentView().tabItem({ Label("THREE", systemImage: "3.circle") })
        }
    }
}

//// TODO: We could try to use Kotlin class and property delegates to minimize synthesized code
//// in both views and ObservableObject types
//class ContentView: View() {
//    // TODO: Add lazy instantiation to avoid recreating on each compose
//    /* @StateObject */ var model = ModelObservableObject()
//    // Synthesized for @StateObject vars
//    init {
//        model.objectWillChange = { onObservableWillChange() }
//    }
//    /* @StateObject */ var envObject = EnvironmentObservableObject()
//    // Normally would setup objectWillChange here, but we don't have multiple subscriber
//    // support implemented yet, and we want our downstream view to be the subscriber
//
//    /* @State */ var tapCount = 0
//        // Synthesized for @State vars
//        set(value) {
//            field = value
//            onStateDidChange()
//        }
//    /* @State */ var isSheetPresented = false
//        // Synthesized for @State vars
//        set(value) {
//            field = value
//            onStateDidChange()
//        }
//    fun makeBinding_isSheetPresented(): Binding<Boolean> {
//        return Binding(get = { isSheetPresented }, set = { isSheetPresented = it })
//    }
//
//    fun body(): View {
//        // TODO: Implement .navigationDestination modifier instead of passing in the mapping function
//        return NavigationStack({ item ->
//            when(item) {
//                "ONE" -> DestinationOne()
//                "TWO" -> DestinationTwo()
//                else -> TextView("ERROR")
//            }
//        }) {
//            VStackView {
//                listOf(
//                    TextView("Outer tap count: $tapCount")
//                        .font("title"),
//                    CustomView(model)
//                        .environmentObject(envObject)
//                        .padding(4)
//                        .background(Color.Yellow)
//                        .border(2),
//                    ButtonView(onClick = {
//                        logger.info("model.modelValue += 1")
//                        model.modelValue += 1
//                        // NOTE: This is forcing recomposition and a re-call of CustomView(). To test
//                        // that CustomView responds to "model" updates independently, comment this out
//                        tapCount += 1
//                    }),
//                    ButtonView(onClick = {
//                        logger.info("environmentObjectValue += 1")
//                        envObject.environmentObjectValue += 1
//                    }),
//                    // TODO: I removed bottom sheet because its layout conflicts with the tabs.
//                    // Need to figure it out with Android Scaffold layouts
////                    TextView("Bottom sheet presented: $isSheetPresented"),
////                    ButtonView(onClick = { isSheetPresented = !isSheetPresented }),
//                )
//            }
//        }
////            .sheet(/* $isSheetPresented */makeBinding_isSheetPresented()) {
////                TextView("Bottom sheet")
////            }
//    }
//
//    // Synthesized
//    @Stable
//    class State(tapCount: Int, isSheetPresented: Boolean, model: ModelObservableObject, envObject: EnvironmentObservableObject) {
//        var tapCount by mutableStateOf(tapCount)
//        var isSheetPresented by mutableStateOf(isSheetPresented)
//        var model by mutableStateOf(model)
//        var envObject by mutableStateOf(envObject)
//    }
//    @Composable
//    override fun Compose(context: ComposeContext) {
//        var isFirstCompose by remember { mutableStateOf(true) }
//        SideEffect {
//            isFirstCompose = false
//        }
//
//        // Remember @State and @StateObjects. If we don't have remembered state (isFirstCompose == true),
//        // then see if the context's state graph has state we can restore from. Composables lose even
//        // remembered state when navigating away, and this is how we restore our tabs and back stacks
//        val restoreState = if (isFirstCompose) context.restoreStateNode?.value as? State else null
//        logger.warning("Compose ContentView isFirstCompose=$isFirstCompose, restore state = ${context.restoreStateNode?.value})")
//        val state = remember { restoreState ?: State(tapCount, isSheetPresented, model, envObject) }
//        // Populate restore state for next time in case we navigate away
//        context.restoreStateNode?.value = state
//        // Sync view state with remembered / restored state
//        tapCount = state.tapCount
//        isSheetPresented = state.isSheetPresented
//        model = state.model
//        envObject = state.envObject
//        // Sync back on @State change
//        onStateDidChange = {
//            state.tapCount = tapCount
//            state.isSheetPresented = isSheetPresented
//        }
//
//        // Keep an observation count for ObservableObjects: @StateObject, @ObservedObject, @EnvironmentObject
//        var observationCount by remember { mutableStateOf(0) }
//        onObservableWillChange = {
//            observationCount += 1
//        }
//        // Read observation count var to add it to the Compose state. Otherwise it will not trigger recompose
//        var tmp = observationCount
//
//        // Compose body view graph
//        body().Compose(context.push("ContentView.body"))
//    }
//    var onStateDidChange: () -> Unit = {}
//    var onObservableWillChange: () -> Unit = {}
//}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct ContentView : View {
    @StateObject var model = ModelObservableObject()
    @StateObject var envObject = EnvironmentObservableObject()
    @State var tapCount = 0
    @State var navPath: [String] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack {
                Text("Outer tap count: \(tapCount)")
                    .font(.largeTitle)
                CustomView(model: model)
                    .environmentObject(envObject)
                    .background(Color.yellow)
                    .padding(4)
//                    .border(2)
                ButtonView("model.modelValue += 1") {
                    logger.info("model.modelValue += 1")
                    model.modelValue += 1
                    // NOTE: This is forcing recomposition and a re-call of CustomView(). To test
                    // that CustomView responds to "model" updates independently, comment this out
                    tapCount += 1
                }
                ButtonView("environmentObjectValue += 1") {
                    logger.info("environmentObjectValue += 1")
                    envObject.environmentObjectValue += 1
                }
                // TODO: I removed bottom sheet because its layout conflicts with the tabs.
                // Need to figure it out with Android Scaffold layouts
//                    TextView("Bottom sheet presented: $isSheetPresented"),
//                    ButtonView(onClick = { isSheetPresented = !isSheetPresented }),
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "ONE":
                    DestinationOne()
                case "TWO":
                    DestinationTwo()
                default:
                    fatalError("unexpected destination: \(destination)")
                }
            }
        }
    }
}


//class CustomView(/* @ObservedObject */ var model: ModelObservableObject): View() {
//    // Synthesized for @ObservedObject vars
//    init {
//        model.objectWillChange = { onObservableWillChange() }
//    }
//
//    /* @StateObject */ var stateObject = StateObservableObject()
//        // Synthesized for @StateObject vars
//        set(value) {
//            field = value
//            stateObject.objectWillChange = { onObservableWillChange() }
//        }
//
//    /* @State */ var tapCount = 0
//        // Synthesized for @State vars
//        set(value) {
//            field = value
//            onStateDidChange()
//        }
//    /* @State */ var textFieldValue = "Initial"
//        // Synthesized for @State vars
//        set(value) {
//            field = value
//            onStateDidChange()
//        }
//    fun makeBinding_textFieldValue(): Binding<String> {
//        return Binding(get = { textFieldValue }, set = { textFieldValue = it })
//    }
//
//    /* @EnvironmentObject */ lateinit var envObject: EnvironmentObservableObject
//
//    fun body(): View {
//        return VStackView { listOf(
//            TextView("Model value: ${model.modelValue}"),
//            TextView("EnvironmentObject value: ${envObject.environmentObjectValue}"),
//            TextView("StateObject value: ${stateObject.stateValue}")
//                .background(Color.Green),
//            ButtonView(onClick = { stateObject.stateValue += 1 }),
//            TextView("Tap count: ${tapCount}")
//                .background(Color.Green),
//            ButtonView(onClick = { onTap() }),
//            TextFieldView(makeBinding_textFieldValue())
//                .fixedSize(),
//            ButtonView(onClick = { textFieldValue = "" }),
//            NavigationLink("One", "ONE"),
//        )}
//    }
//
//    fun onTap() {
//        tapCount += 1
//    }
//
//    // Synthesized
//    @Stable
//    class State(tapCount: Int, textFieldValue: String, stateObject: StateObservableObject) {
//        var tapCount by mutableStateOf(tapCount)
//        var textFieldValue by mutableStateOf(textFieldValue)
//        var stateObject by mutableStateOf(stateObject)
//    }
//    @Composable
//    override fun Compose(context: ComposeContext) {
//        // Initialize each @EnvironmentObject var
//        // TODO: Real Environment support with efficient lookups
//        envObject = context.environment.objects.last { it is EnvironmentObservableObject } as EnvironmentObservableObject
//        envObject.objectWillChange = { onObservableWillChange() }
//
//        // Same synthesized state remember and restore pattern as ContentView.Compose
//        var isFirstCompose by remember { mutableStateOf(true) }
//        SideEffect {
//            isFirstCompose = false
//        }
//        val restoreState = if (isFirstCompose) context.restoreStateNode?.value as? State else null
//        logger.warning("Compose CustomView isFirstCompose=$isFirstCompose, restore state = ${context.restoreStateNode?.value})")
//        val state = remember { restoreState ?: State(tapCount, textFieldValue, stateObject) }
//        context.restoreStateNode?.value = state
//
//        tapCount = state.tapCount
//        textFieldValue = state.textFieldValue
//        stateObject = state.stateObject
//        // Sync back on change
//        onStateDidChange = {
//            state.tapCount = tapCount
//            state.textFieldValue = textFieldValue
//        }
//
//        var observationCount by remember { mutableStateOf(0) }
//        onObservableWillChange = {
//            observationCount += 1
//        }
//        var tmp = observationCount
//
//        body().Compose(context.push("CustomView.body"))
//    }
//    var onStateDidChange: () -> Unit = {}
//    var onObservableWillChange: () -> Unit = {}
//}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CustomView : View {
    @StateObject var model: ModelObservableObject
    @StateObject var stateObject = StateObservableObject()
    @State var tapCount = 0
    @State var textFieldValue = "Initial"
    @EnvironmentObject var envObject: EnvironmentObservableObject

    func onTap() {
        tapCount += 1
    }

    //    // Synthesized
    //    @Stable
    //    class State(tapCount: Int, textFieldValue: String, stateObject: StateObservableObject) {
    //        var tapCount by mutableStateOf(tapCount)
    //        var textFieldValue by mutableStateOf(textFieldValue)
    //        var stateObject by mutableStateOf(stateObject)
    //    }

    var body: some View {
        VStack {
            Text("Model value: \(model.modelValue)")
            Text("EnvironmentObject value: \(envObject.environmentObjectValue)")
            Text("StateObject value: \(stateObject.stateValue)")
                .background(Color.green)
            ButtonView { stateObject.stateValue += 1 }

            Text("Tap count: \(tapCount)")
                .background(Color.green)
            ButtonView(onClick: { onTap() })
            TextFieldView(text: $textFieldValue)
                .fixedSize()
            ButtonView("Clear Text", onClick: { textFieldValue = "" })
            NavigationLink("Navigate: One", value: "ONE")
            #if os(iOS)
                .isDetailLink(true)
            #endif
        }
    }
}


class ModelObservableObject : ObservableObject {
    @Published var modelValue = 0
}

class StateObservableObject : ObservableObject {
    @Published var stateValue = 0
}

class EnvironmentObservableObject : ObservableObject {
    @Published var environmentObjectValue = 0
}

#endif
