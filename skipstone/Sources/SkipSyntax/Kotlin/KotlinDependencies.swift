/// Track additional dependencies needed by transpiled Kotlin code.
struct KotlinDependencies {
    /// Package names to import, e.g. "kotlin.reflect.\*".
    var imports: Set<String> = []
    // Note: we could expand this to track gradle or other dependencies as well
}

/// Known dependency sets.
extension KotlinDependencies {
    /// Add an explicit import of the given `skip.lib` type.
    mutating func insertSkipLibType(_ typeName: String) {
        imports.insert("skip.lib.\(typeName)")
    }

    /// Add a dependency on `kotlin.reflect`.
    mutating func insertReflect() {
        imports.insert("kotlin.reflect.KClass")
    }

    /// Add a dependency on `kotlin.reflect.full`.
    mutating func insertReflectFull() {
        imports.insert("kotlin.reflect.full.companionObjectInstance")
    }
}
