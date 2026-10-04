fun main() {
    try {
        StringBuilder("hello").insert(99, "x")
        println("insert: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("insert: caught")
    }

    try {
        StringBuilder("hello").insert(99, 'x')
        println("insertChar: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("insertChar: caught")
    }

    try {
        StringBuilder("hello").insert(99, true)
        println("insertBoolean: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("insertBoolean: caught")
    }

    try {
        StringBuilder("hello").insert(99, 3.14f)
        println("insertFloat: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("insertFloat: caught")
    }

    try {
        StringBuilder("hello").insert(99, 2.718)
        println("insertDouble: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("insertDouble: caught")
    }

    try {
        StringBuilder("hello").delete(99, 100)
        println("delete: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("delete: caught")
    }

    try {
        StringBuilder("hello").deleteCharAt(99)
        println("deleteCharAt: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("deleteCharAt: caught")
    }

    try {
        StringBuilder("hello").get(99)
        println("get: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("get: caught")
    }

    try {
        StringBuilder("hello").setCharAt(99, 'x')
        println("setCharAt: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("setCharAt: caught")
    }

    try {
        StringBuilder("hello").replace(99, 100, "x")
        println("replace: no exception")
    } catch (e: IndexOutOfBoundsException) {
        println("replace: caught")
    }
}
