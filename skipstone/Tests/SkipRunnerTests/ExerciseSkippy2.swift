/// A second file to exercise Skippy on multi-file modules.

func f2(param: Int) -> Int {
    return param + 1
}

struct ArrayHolder {
    var array = [0] {
        didSet {
            arraySets += 1
        }
    }
    var arraySets = 0

    mutating func addToFirst(value: Int) {
        array[0] += value
    }

    func appending(value: Int) -> ArrayHolder {
        var holder = self
        holder.array.append(value)
        return holder
    }
}
