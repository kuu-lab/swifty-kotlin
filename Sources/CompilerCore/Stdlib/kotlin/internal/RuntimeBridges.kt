package kotlin.internal

@KsSymbolName("__kk_values_equal")
internal external fun __valuesEqual(lhs: Any?, rhs: Any?): Boolean

@KsSymbolName("__kk_array_contentDeepEquals")
internal external fun __arrayContentDeepEquals(array: Any?, other: Any?): Boolean

@KsSymbolName("__kk_array_contentDeepToString")
internal external fun __arrayContentDeepToString(array: Any?): String

@KsSymbolName("__kk_array_contentDeepHashCode")
internal external fun __arrayContentDeepHashCode(array: Any?): Int
