package SkipFoundation

interface ValueType {
    fun valueCopy(): Any
}

fun <T> T.valueReference(): T {
    if (this is ValueType) {
        return valueCopy() as T
    }
    return this
}
