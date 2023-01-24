import Foundation

struct UnsupportedTypes {
}

func unsupportedFunction() {
}

#if DEBUG
let unsupportedLet = 0
#else
let unsupportedLet = 1
#endif
