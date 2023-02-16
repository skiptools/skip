import SkipUI

struct DestinationOne : View {
    @State var x = 1
    
    var body: some View {
        VStack {
            Text("ONE")
                .font(.title)
            NavigationLink(value: "TWO", label: { Text("Two") })
        }
    }
}
