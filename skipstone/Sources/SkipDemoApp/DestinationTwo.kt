package skip.demo.app

import androidx.compose.runtime.Composable

class DestinationTwo: View() {
    fun body(): View {
        return TextView("TWO")
            .font("title")
    }

    // Synthesized
    @Composable
    override fun Compose(context: ComposeContext) {
        body().Compose(context)
    }
}
