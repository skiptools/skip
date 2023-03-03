package skip.kotlin

interface ValueSemantics {
    fun valcopy(): ValueSemantics
    var valupdate: ((Any) -> Unit)?
}

@Suppress("UNCHECKED_CAST")
fun <T> T.valref(onUpdate: ((T) -> Unit)? = null): T {
    if (this is ValueSemantics) {
        val copy = valcopy()
        copy.valupdate = {
            if (onUpdate != null) {
                onUpdate(it as T)
            }
        }
        return copy as T
    }
    return this
}
