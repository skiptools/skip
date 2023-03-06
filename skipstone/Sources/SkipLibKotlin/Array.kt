package skip.lib

fun <T> arrayOf(vararg elements: T): Array<T> {
    val array = Array<T>()
    for (element in elements) {
        array.append(element)
    }
    return array
}

class Array<T>: MutableStruct, Iterable<T> {
    private var storage: ArrayStorage<T>
    private var isStorageShared = false

    constructor() {
        storage = ArrayStorage()
    }

    constructor(collection: Collection<T>) {
        storage = ArrayStorage()
        for (element in collection) {
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
        val storageIterator = storage.iterator()
        return object: Iterator<T> {
            override fun hasNext(): Boolean {
                return storageIterator.hasNext()
            }
            override fun next(): T {
                return storageIterator.next().sref()
            }
        }
    }

    operator fun get(index: Int): T {
        return storage[index].sref({
            set(index, it)
        })
    }

    operator fun set(index: Int, element: T) {
        copyStorageIfNeeded()
        willmutate()
        storage[index] = element.sref()
        didmutate()
    }

    fun append(element: T) {
        copyStorageIfNeeded()
        willmutate()
        storage.add(element.sref())
        didmutate()
    }

    val count: Int
        get() = storage.count()

    override fun equals(other: Any?): Boolean {
        if (other === this) {
            return true
        }
        if (other as? Array<*> == null) {
            return false
        }
        return other.storage == storage
    }

    override var supdate: ((Any) -> Unit)? = null
    override var smutatingcount = 0
    override fun scopy(): MutableStruct {
        isStorageShared = true
        return Array(storage = storage)
    }

    private fun copyStorageIfNeeded() {
        if (isStorageShared) {
            storage = ArrayStorage(storage)
            isStorageShared = false
        }
    }

    private class ArrayStorage<T>(): ArrayList<T>() {
        constructor(list: List<T>) : this() {
            addAll(list)
        }
    }
}
