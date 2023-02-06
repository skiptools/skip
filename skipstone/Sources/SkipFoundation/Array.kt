package SkipFoundation

fun <T> arrayOf(vararg elements: T): Array<T> {
    val array = Array<T>()
    for (element in elements) {
        array.append(element)
    }
    return array
}

class Array<T>: ValueType, Iterable<T> {
    private val storage: ArrayList<T>

    constructor() {
        storage = ArrayList<T>()
    }

    constructor(list: List<T>) {
        storage = ArrayList(list)
    }

    constructor(vararg elements: T) {
        val storage = ArrayList<T>()
        for (element in elements) {
            storage.add(element)
        }
        this.storage = storage
    }

    override fun iterator(): Iterator<T> {
        return storage.iterator()
    }

    fun append(element: T) {
        storage.add(element)
    }

    val count: Int
        get() = storage.count()

    override fun valueCopy(): Any {
        return Array(storage.map { it.valueReference() })
    }

    override fun equals(other: Any?): Boolean {
        if (other === this) {
            return true
        }
        if (other as? Array<T> == null) {
            return false
        }
        return other.storage == storage
    }
}
