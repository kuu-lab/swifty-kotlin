package java.lang

typealias IllegalArgumentException = kotlin.IllegalArgumentException
open class IllegalAccessException: kotlin.Exception { constructor(): super() }
open class StringIndexOutOfBoundsException: kotlin.IndexOutOfBoundsException { constructor(): super(); constructor(message: String?): super(message); constructor(index: Int): super("String index out of range") }
