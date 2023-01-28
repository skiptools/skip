// Header comment

import /* Middle comment */ Foundation // Trailing import comment
// That continues here

// Standalone comment

// Decl comment
struct UnsupportedTypes1 { // Trailing comment
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
