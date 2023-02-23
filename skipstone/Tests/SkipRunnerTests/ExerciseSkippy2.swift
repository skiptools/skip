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

    func f() {
        if (p1 < 0 || p1 > 1) && p1 < 100 {
            print("yes")
        }
    }
}
