import SkipUI

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct DestinationOne : View {
    var body: some View {
        VStack {
            Text("ONE")
                .font(.title)
            NavigationLink(value: "TWO", label: { Text("Two") })
        }
    }
}
