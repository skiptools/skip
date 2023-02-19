import SkipUI

struct DestinationOne : View {
    var body: some View {
        VStack {
            Text("ONE")
                .font(.title)
            NavigationLink(value: "TWO", label: { Text("Two") })
        }
    }
}
