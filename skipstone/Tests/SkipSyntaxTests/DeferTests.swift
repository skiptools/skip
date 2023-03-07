@testable import SkipSyntax
import XCTest

final class DeferTests: XCTestCase {
    func testFunctionDefer() async throws {
        try await check(swift: """
        func f() {
            let handle: Int = open()
            defer { close(handle) }
            print(handle)
        }
        """, kotlin: """
        internal fun f() {
            var deferaction: (() -> Unit)? = null
            try {
                val handle: Int = open()
                deferaction = {
                    close(handle)
                }
                print(handle)
            } finally {
                deferaction?.invoke()
            }
        }
        """)
    }

    func testMultipleFunctionDefers() async throws {
        try await check(swift: """
        func f() {
            let handle1: Int = open()
            defer { close(handle1) }
            print(handle1)
            let handle2: Int = open()
            defer { close(handle2) }
            print(handle2)
            doSomethingWithHandles(handle1, handle2)
        }
        """, kotlin: """
        internal fun f() {
            val deferactions: MutableList<() -> Unit> = mutableListOf()
            try {
                val handle1: Int = open()
                deferactions.add {
                    close(handle1)
                }
                print(handle1)
                val handle2: Int = open()
                deferactions.add {
                    close(handle2)
                }
                print(handle2)
                doSomethingWithHandles(handle1, handle2)
            } finally {
                deferactions.asReversed().forEach { it.invoke() }
            }
        }
        """)
    }

    func testBlockDefers() async throws {
        try await check(swift: """
        func f() {
            let handle1: Int = open()
            defer { close(handle1) }
            if needsTwoHandles {
                let handle2: Int = open()
                defer { close(handle2) }
                print(handle2)
            }
            print(handle1)
        }
        """, kotlin: """
        internal fun f() {
            var deferaction: (() -> Unit)? = null
            try {
                val handle1: Int = open()
                deferaction = {
                    close(handle1)
                }
                if (needsTwoHandles) {
                    var deferaction: (() -> Unit)? = null
                    try {
                        val handle2: Int = open()
                        deferaction = {
                            close(handle2)
                        }
                        print(handle2)
                    } finally {
                        deferaction?.invoke()
                    }
                }
                print(handle1)
            } finally {
                deferaction?.invoke()
            }
        }
        """)
    }
}
