package skip.kotlin

// These types are not themselves mutable, but their members might be, and a destructuring assignment can
// access members without calling valref() on them. So support valref() on the tuples themselves. Note that
// because the tuples aren't mutable, we can ignore the onUpdate closure

fun <A, B> Pair<A, B>.valref(onUpdate: ((Pair<A, B>) -> Unit)? = null): Pair<A, B> {
    val firstRef = first.valref()
    val secondRef = second.valref()
    if (firstRef !== first || secondRef !== second) {
        return Pair(firstRef, secondRef)
    }
    return this
}

fun <A, B, C> Triple<A, B, C>.valref(onUpdate: ((Triple<A, B, C>) -> Unit)? = null): Triple<A, B, C> {
    val firstRef = first.valref()
    val secondRef = second.valref()
    val thirdRef = third.valref()
    if (firstRef !== first || secondRef !== second || thirdRef !== third) {
        return Triple(firstRef, secondRef, thirdRef)
    }
    return this
}
