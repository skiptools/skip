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
            var deferaction_0: (() -> Unit)? = null
            try {
                val handle: Int = open()
                deferaction_0 = {
                    close(handle)
                }
                print(handle)
            } finally {
                deferaction_0?.invoke()
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
            val deferactions_0: MutableList<() -> Unit> = mutableListOf()
            try {
                val handle1: Int = open()
                deferactions_0.add {
                    close(handle1)
                }
                print(handle1)
                val handle2: Int = open()
                deferactions_0.add {
                    close(handle2)
                }
                print(handle2)
                doSomethingWithHandles(handle1, handle2)
            } finally {
                deferactions_0.asReversed().forEach { it.invoke() }
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
            var deferaction_0: (() -> Unit)? = null
            try {
                val handle1: Int = open()
                deferaction_0 = {
                    close(handle1)
                }
                if (needsTwoHandles) {
                    var deferaction_1: (() -> Unit)? = null
                    try {
                        val handle2: Int = open()
                        deferaction_1 = {
                            close(handle2)
                        }
                        print(handle2)
                    } finally {
                        deferaction_1?.invoke()
                    }
                }
                print(handle1)
            } finally {
                deferaction_0?.invoke()
            }
        }
        """)
    }
}
