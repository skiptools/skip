/// A second file to exercise Skippy on multi-file modules.

func f2() throws -> Int? {
    return try? f3()
}

func f3() throws -> Int {
    return 1
}

struct S {
    var p1: Int
    var p2: String?

    static func factory() -> S {
        return S(p1: 1)
    }

    static func factory2() -> S {
        return .init(p1: 1)
    }

//    init(p1: Int) {
//        self.p1 = p1
//        self.p2 = "foo"
//    }
}
