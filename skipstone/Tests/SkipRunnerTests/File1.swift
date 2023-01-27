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
    var x: Int { get set }
}

// SKIP INSERT: Hello from
// Skip!
// Another

func unsupportedFunction1() {
}

#if SKIP
protocol IfProtocol {}
#else
protocol ElseProtocol {}
#endif
