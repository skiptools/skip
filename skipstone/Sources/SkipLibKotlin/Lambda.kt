package skip.lib

// Immediately-executed Kotlin lambda expressions do not support return statements. In order to support returns,
// we call these functions with the target lambda instead

fun <R> linvoke(l: () -> R): R {
    return l()
}

fun <P0, R> linvoke(p0: P0, l: (P0) -> R): R {
    return l(p0)
}

fun <P0, P1, R> linvoke(p0: P0, p1: P1, l: (P0, P1) -> R): R {
    return l(p0, p1)
}

fun <P0, P1, P2, R> linvoke(p0: P0, p1: P1, p2: P2, l: (P0, P1, P2) -> R): R {
    return l(p0, p1, p2)
}

fun <P0, P1, P2, P3, R> linvoke(p0: P0, p1: P1, p2: P2, p3: P3, l: (P0, P1, P2, P3) -> R): R {
    return l(p0, p1, p2, p3)
}

fun <P0, P1, P2, P3, P4, R> linvoke(p0: P0, p1: P1, p2: P2, p3: P3, p4: P4, l: (P0, P1, P2, P3, P4) -> R): R {
    return l(p0, p1, p2, p3, p4)
}

fun <P0, P1, P2, P3, P4, P5, R> linvoke(p0: P0, p1: P1, p2: P2, p3: P3, p4: P4, p5: P5, l: (P0, P1, P2, P3, P4, P5) -> R): R {
    return l(p0, p1, p2, p3, p4, p5)
}

fun <P0, P1, P2, P3, P4, P5, P6, R> linvoke(p0: P0, p1: P1, p2: P2, p3: P3, p4: P4, p5: P5, p6: P6, l: (P0, P1, P2, P3, P4, P5, P6) -> R): R {
    return l(p0, p1, p2, p3, p4, p5, p6)
}

fun <P0, P1, P2, P3, P4, P5, P6, P7, R> linvoke(p0: P0, p1: P1, p2: P2, p3: P3, p4: P4, p5: P5, p6: P6, p7: P7, l: (P0, P1, P2, P3, P4, P5, P6, P7) -> R): R {
    return l(p0, p1, p2, p3, p4, p5, p6, p7)
}
