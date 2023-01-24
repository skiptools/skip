import Foundation

struct UnsupportedTypes1 {
}

func unsupportedFunction1() {
}

#if DEBUG
let unsupportedLet = 0
#else
let unsupportedLet = 1
#endif
