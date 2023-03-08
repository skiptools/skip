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

    func testEnumHasAssociatedValues() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.enumHasAssociatedValues(qualifiedName: "NonExistantTypeName"))

        XCTAssertEqual(false, context.enumHasAssociatedValues(qualifiedName: "KotlinCodebaseInfoTestsEnum"))
        XCTAssertEqual(true, context.enumHasAssociatedValues(qualifiedName: "KotlinCodebaseInfoTestsEnumWithAssociatedValues"))
    }
}

class KotlinCodebaseInfoTestsClass {
}

enum KotlinCodebaseInfoTestsEnum: Int {
    case case1
    case case2 = 100
}
enum KotlinCodebaseInfoTestsEnumWithAssociatedValues {
    case case1
    case case2(Int)
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
