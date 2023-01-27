// Header comment

import Foundation

// Standalone comment

// Decl comment
// SKIP FOO
struct UnsupportedTypes1 {
}

// Protocol comment
// SKIP DECLARE: interface FooBar<X>
protocol UnsupportedProtocol {
}

// SKIP INSERT: Hello from
// Skip!
// Another

func unsupportedFunction1() {
}

#if SKIP
let unsupportedLet = 0
#else
let unsupportedLet = 1
#endif

// Footer comment
