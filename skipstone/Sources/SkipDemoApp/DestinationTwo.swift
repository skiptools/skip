import SkipUI

// SKIP INSERT: import androidx.compose.runtime.Composable

let destinationTwoTitle = "TWO"

// SKIP REPLACE: class DestinationTwo(val title: String = destinationTwoTitle) : View() { @Composable override fun Compose(context: ComposeContext) { body().Compose(context) } }
struct DestinationTwo : View {
    let title: String = destinationTwoTitle
}

// SKIP REPLACE: fun DestinationTwo.body() : View { return createTextView().font("title") }
extension DestinationTwo {
    var body: some View {
        createTextView().font(.title)
    }
}

extension DestinationTwo {
    func createTextView() -> TextView {
        return TextView(title)
    }
}
