/// A second file to exercise SkipCheck on multi-file modules.

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
        for i in 0..<10 {
            print(i)
        }
    }
}
