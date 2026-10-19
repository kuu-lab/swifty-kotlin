package java.lang

import kotlin.IndexOutOfBoundsException
import kotlin.internal.KsSymbolName

public open class StringIndexOutOfBoundsException : IndexOutOfBoundsException {
    @KsSymbolName("__kk_string_index_out_of_bounds_exception_new")
    public constructor()

    @KsSymbolName("__kk_string_index_out_of_bounds_exception_new_message")
    public constructor(message: String?)

    public constructor(index: Int) : this("String index out of range: $index")
}
