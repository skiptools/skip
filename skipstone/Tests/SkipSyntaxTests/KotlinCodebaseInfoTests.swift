@testable import SkipSyntax
import XCTest

final class KotlinCodebaseInfoTests: XCTestCase {
    func testIsMutableValueType() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.isMutableValueType(qualifiedName: "NonExistantTypeName"))

        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsClass"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsEnum"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsImmutableStruct"))

        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsMutableVarStruct"))
        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsMutableComputedVarStruct"))
        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsMutableFuncStruct"))

        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol"))
    }
}

class KotlinCodebaseInfoTestsClass {
}

enum KotlinCodebaseInfoTestsEnum {
    case case1
    case case2
}

struct KotlinCodebaseInfoTestsImmutableStruct {
    let letVar = 1
}

struct KotlinCodebaseInfoTestsMutableVarStruct {
    var v = 1
}

struct KotlinCodebaseInfoTestsMutableComputedVarStruct {
    var computedVar: Int {
        get {
            return 1
        }
        set {
        }
    }
}

struct KotlinCodebaseInfoTestsMutableFuncStruct {
    mutating func f() -> Int {
        return 1
    }
}

protocol KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol: Codable {}
protocol KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol: AnyObject {}
protocol KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol: KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol {}
