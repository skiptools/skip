/// Indentation helper.
struct Indentation: ExpressibleByIntegerLiteral, CustomStringConvertible {
    static let zero = Indentation(level: 0)
    
    let level: Int

    init(level: Int) {
        self.level = level
    }

    init(integerLiteral: Int) {
        self.level = integerLiteral
    }

    func inc() -> Indentation {
        return Indentation(level: level + 1)
    }

    func dec() -> Indentation {
        return Indentation(level: max(0, level - 1))
    }

    var description: String {
        return String(repeating: "    ", count: level)
    }
}
