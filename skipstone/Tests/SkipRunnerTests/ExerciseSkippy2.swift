/// A second file to exercise Skippy on multi-file modules.

func f2(param: Int) -> Int {
    return param > 0 ? (param + 1) * 3 : 2
}

func f3(param: Bool) -> Int {
    let p: Bool
    p = param
    return p ? 0 : 1
}
