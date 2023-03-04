@testable import SkipSyntax
import XCTest

final class KotlinCodebaseInfoTests: XCTestCase {
    func testIsMutableStructType() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.isMutableStructType(qualifiedName: "NonExistantTypeName"))

        XCTAssertEqual(false, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsClass"))
        XCTAssertEqual(false, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsEnum"))
        XCTAssertEqual(false, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsImmutableStruct"))

        XCTAssertEqual(true, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsMutableVarStruct"))
        XCTAssertEqual(true, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsMutableComputedVarStruct"))
        XCTAssertEqual(true, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsMutableFuncStruct"))

        XCTAssertEqual(true, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, context.isMutableStructType(qualifiedName: "KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol"))
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
