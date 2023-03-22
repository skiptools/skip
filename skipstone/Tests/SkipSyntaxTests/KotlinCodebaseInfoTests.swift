@testable import SkipSyntax
import XCTest

// to update the codebase symbols for this test, manually run:

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

    func testProtocolTypeHasMember() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.protocolOf(qualifiedName: "NonExistantTypeName", hasMember: "protocolVar", kind: .property, type: nil))

        XCTAssertEqual(false, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol", hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", hasMember: "baseProtocolVar", kind: .property, type: .int))
        XCTAssertEqual(false, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", hasMember: "baseProtocolVar", kind: .property, type: .string))

        let functionType: TypeSignature = .function([.init(label: "i", type: .int)], .string)
        XCTAssertEqual(false, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol", hasMember: "baseProtocolFunc", kind: .method, type: functionType))
        XCTAssertEqual(true, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", hasMember: "baseProtocolFunc", kind: .method, type: functionType))
        XCTAssertEqual(false, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", hasMember: "baseProtocolFunc", kind: .method, type: .function([.init(label: "i", type: .string)], .string)))

        XCTAssertEqual(true, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol", hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol", hasMember: "baseProtocolFunc", kind: .method, type: functionType))

        XCTAssertEqual(true, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsProtocolImpl", hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(qualifiedName: "KotlinCodebaseInfoTestsProtocolImpl", hasMember: "baseProtocolFunc", kind: .method, type: functionType))
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
protocol KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol: AnyObject {
    var baseProtocolVar: Int { get }
    func baseProtocolFunc(i: Int) -> String
}
protocol KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol: KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol {
}
class KotlinCodebaseInfoTestsProtocolImpl: KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol {
    var baseProtocolVar = 1
    func baseProtocolFunc(i: Int) -> String {
        return ""
    }
}
