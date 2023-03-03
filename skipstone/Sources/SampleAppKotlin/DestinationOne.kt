package sample.app

import androidx.compose.runtime.Composable

class DestinationOne: View() {
    fun body(): View {
        return VStackView { listOf(
            TextView("ONE")
                .font("title"),
            NavigationLink("Two", "TWO")
        )}
    }

    // Synthesized
    @Composable
    override fun Compose(context: ComposeContext) {
        body().Compose(context)
    }
}
