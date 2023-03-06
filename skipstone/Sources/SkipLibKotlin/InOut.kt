package skip.lib

class InOut<T>(val get: () -> T, val set: (T) -> Unit) {
    var value: T
        get() = this.get()
        set(newValue) = this.set(newValue)
}
