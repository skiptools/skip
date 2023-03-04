package skip.lib

interface MutableStruct {
    fun scopy(): MutableStruct
    var supdate: ((Any) -> Unit)?
}

@Suppress("UNCHECKED_CAST")
fun <T> T.sref(onUpdate: ((T) -> Unit)? = null): T {
    if (this is MutableStruct) {
        val copy = scopy()
        copy.supdate = {
            if (onUpdate != null) {
                onUpdate(it as T)
            }
        }
        return copy as T
    }
    return this
}
