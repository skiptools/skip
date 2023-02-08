package skip.foundation

fun <T> arrayOf(vararg elements: T): Array<T> {
    val array = Array<T>()
    for (element in elements) {
        array.append(element)
    }
    return array
}

class Array<T>: ValueSemantics, Iterable<T> {
    private var storage: ArrayStorage<T>
    private var isStorageShared = false

    constructor() {
        storage = ArrayStorage()
    }

    constructor(list: List<T>) {
        storage = ArrayStorage()
        for (element in list) {
            append(element)
        }
    }

    constructor(vararg elements: T) {
        storage = ArrayStorage()
        for (element in elements) {
            append(element)
        }
    }

    private constructor(storage: ArrayStorage<T>) {
        this.storage = storage
        isStorageShared = true
    }

    override fun iterator(): Iterator<T> {
        return storage.iterator()
    }

    operator fun get(index: Int): T {
        return storage[index]
    }

    fun append(element: T) {
        if (isStorageShared) {
            storage = ArrayStorage(storage)
            isStorageShared = false
        }
        storage.add(element.valref({ this.onUpdate?.invoke() }))
        onUpdate?.invoke()
    }

    val count: Int
        get() = storage.count()

    override fun equals(other: Any?): Boolean {
        if (other === this) {
            return true
        }
        if (other as? Array<T> == null) {
            return false
        }
        return other.storage == storage
    }

    override var onUpdate: (() -> Unit)? = null

    override fun valcopy(): ValueSemantics {
        var copy: Array<T>? = null
        for (i in 0 until storage.count()) {
            val valref = storage[i].valref({ this.onUpdate?.invoke() })
            if (copy != null) {
                copy.storage.add(valref)
            } else if (valref !== storage[i]) {
                copy = Array()
                copy.storage.addAll(storage.slice(0 until i))
                copy.storage.add(valref)
            }
        }
        if (copy != null) {
            return copy
        }

        // We didn't find any elements that needed copying, so share storage
        isStorageShared = true
        return Array(storage = storage)
    }

    private class ArrayStorage<T>(): ArrayList<T>() {
        constructor(list: List<T>) : this() {
            addAll(list)
        }
    }
}
