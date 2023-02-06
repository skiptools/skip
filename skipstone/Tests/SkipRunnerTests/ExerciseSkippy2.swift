/// A second file to exercise Skippy on multi-file modules.

func f2(param: Int) -> Int {
    return param + 1
}

struct ArrayHolder {
    var array: [Int] = []

    mutating func add(value: Int) {
        array.append(value)
    }

    func adding(value: Int) -> ArrayHolder {
        var holder = self
        holder.array.append(value)
        return holder
    }
}
