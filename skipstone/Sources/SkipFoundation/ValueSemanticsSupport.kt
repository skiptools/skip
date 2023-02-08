package skip.foundation

interface ValueSemantics {
    fun valcopy(): ValueSemantics
    var onUpdate: (() -> Unit)?
}

fun <T> T.valref(onUpdate: (() -> Unit)? = null): T {
    if (this is ValueSemantics) {
        val copy = valcopy()
        copy.onUpdate = onUpdate
        @Suppress("UNCHECKED_CAST")
        return copy as T
    }
    return this
}
