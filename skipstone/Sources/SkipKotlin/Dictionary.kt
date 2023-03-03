package skip.kotlin

fun <K, V> dictionaryOf(vararg entries: Pair<K, V>): Dictionary<K, V> {
    val dictionary = Dictionary<K, V>()
    for (entry in entries) {
        dictionary[entry.first] = entry.second
    }
    return dictionary
}

class Dictionary<K, V>: ValueSemantics, Iterable<Pair<K, V>> {
    private var storage: DictionaryStorage<K, V>
    private var isStorageShared = false

    constructor() {
        storage = DictionaryStorage()
    }

    constructor(map: Map<K, V>) {
        storage = DictionaryStorage()
        for (entry in map) {
            this[entry.key] = entry.value
        }
    }

    constructor(vararg entries: Pair<K, V>) {
        storage = DictionaryStorage()
        for (entry in entries) {
            this[entry.first] = entry.second
        }
    }

    private constructor(storage: DictionaryStorage<K, V>) {
        this.storage = storage
        isStorageShared = true
    }

    override fun iterator(): Iterator<Pair<K, V>> {
        val storageIterator = storage.iterator()
        return object: Iterator<Pair<K, V>> {
            override fun hasNext(): Boolean {
                return storageIterator.hasNext()
            }
            override fun next(): Pair<K, V> {
                val entry = storageIterator.next()
                return Pair(entry.key.valref(), entry.value.valref())
            }
        }
    }

    operator fun get(key: K): V? {
        return storage[key]?.valref({
            set(key, it)
        })
    }

    operator fun set(key: K, value: V?) {
        copyStorageIfNeeded()
        if (value == null) {
            storage.remove(key)
        } else {
            storage[key] = value.valref()
        }
        valupdate?.invoke(this)
    }

    // TODO: Duplicate Swift's Collection and Sequence types

    val keys: Array<K>
        get() = Array(storage.keys)

    val values: Array<V>
        get() = Array(storage.values)

    val count: Int
        get() = storage.count()

    override fun equals(other: Any?): Boolean {
        if (other === this) {
            return true
        }
        if (other as? Dictionary<*, *> == null) {
            return false
        }
        return other.storage == storage
    }

    override var valupdate: ((Any) -> Unit)? = null

    override fun valcopy(): ValueSemantics {
        isStorageShared = true
        return Dictionary(storage = storage)
    }

    private fun copyStorageIfNeeded() {
        if (isStorageShared) {
            storage = DictionaryStorage(storage)
            isStorageShared = false
        }
    }

    private class DictionaryStorage<K, V>(): HashMap<K, V>() {
        constructor(map: Map<K, V>) : this() {
            putAll(map)
        }
    }
}

val <K, V> Pair<K, V>.key: K
    get() = first
val <K, V> Pair<K, V>.value: V
    get() = second
