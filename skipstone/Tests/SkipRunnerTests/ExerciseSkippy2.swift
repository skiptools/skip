/// A second file to exercise Skippy on multi-file modules.

func f2() throws -> Int? {
    return try? f3()
}

func f3() throws -> Int {
    return 1
}
