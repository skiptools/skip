package skip.lib

// These types are not themselves mutable, but their members might be, and a destructuring assignment can
// access members without calling sref() on them. So support sref() on the tuples themselves. Note that
// because the tuples aren't mutable, we can ignore the onUpdate closures

fun <A, B> Pair<A, B>.sref(onUpdate: ((Pair<A, B>) -> Unit)? = null): Pair<A, B> {
    val firstRef = first.sref()
    val secondRef = second.sref()
    if (firstRef !== first || secondRef !== second) {
        return Pair(firstRef, secondRef)
    }
    return this
}

fun <A, B, C> Triple<A, B, C>.sref(onUpdate: ((Triple<A, B, C>) -> Unit)? = null): Triple<A, B, C> {
    val firstRef = first.sref()
    val secondRef = second.sref()
    val thirdRef = third.sref()
    if (firstRef !== first || secondRef !== second || thirdRef !== third) {
        return Triple(firstRef, secondRef, thirdRef)
    }
    return this
}
