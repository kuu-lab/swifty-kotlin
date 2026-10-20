@file:kotlin.jvm.JvmName("TypeIntrinsics")
package kotlin.jvm.internal
fun getFunctionArity(value: Any?): Int {
    if (value is FunctionBase<*>) return value.arity
    if (value is kotlin.jvm.functions.Function0<*>) return 0
    if (value is kotlin.jvm.functions.Function1<*, *>) return 1
    if (value is kotlin.jvm.functions.Function2<*, *, *>) return 2
    if (value is kotlin.jvm.functions.Function3<*, *, *, *>) return 3
    if (value is kotlin.jvm.functions.Function4<*, *, *, *, *>) return 4
    if (value is kotlin.jvm.functions.Function5<*, *, *, *, *, *>) return 5
    if (value is kotlin.jvm.functions.Function6<*, *, *, *, *, *, *>) return 6
    if (value is kotlin.jvm.functions.Function7<*, *, *, *, *, *, *, *>) return 7
    if (value is kotlin.jvm.functions.Function8<*, *, *, *, *, *, *, *, *>) return 8
    if (value is kotlin.jvm.functions.Function9<*, *, *, *, *, *, *, *, *, *>) return 9
    if (value is kotlin.jvm.functions.Function10<*, *, *, *, *, *, *, *, *, *, *>) return 10
    if (value is kotlin.jvm.functions.Function11<*, *, *, *, *, *, *, *, *, *, *, *>) return 11
    if (value is kotlin.jvm.functions.Function12<*, *, *, *, *, *, *, *, *, *, *, *, *>) return 12
    if (value is kotlin.jvm.functions.Function13<*, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 13
    if (value is kotlin.jvm.functions.Function14<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 14
    if (value is kotlin.jvm.functions.Function15<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 15
    if (value is kotlin.jvm.functions.Function16<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 16
    if (value is kotlin.jvm.functions.Function17<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 17
    if (value is kotlin.jvm.functions.Function18<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 18
    if (value is kotlin.jvm.functions.Function19<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 19
    if (value is kotlin.jvm.functions.Function20<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 20
    if (value is kotlin.jvm.functions.Function21<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 21
    if (value is kotlin.jvm.functions.Function22<*, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *, *>) return 22
    return -1
}
fun isFunctionOfArity(value: Any?, arity: Int): Boolean = value is kotlin.Function<*> && getFunctionArity(value) == arity
fun beforeCheckcastToFunctionOfArity(value: Any?, arity: Int): Any? {
    if (value != null && !isFunctionOfArity(value, arity)) throw ClassCastException("Function arity mismatch")
    return value
}
fun asMutableIterable(value: Any?): kotlin.collections.Iterable<Any?>? {
    if (value is kotlin.jvm.internal.markers.KMappedMarker && !(value is kotlin.jvm.internal.markers.KMutableIterable)) throw ClassCastException("Value cannot be cast to MutableIterable")
    return value as kotlin.collections.Iterable<Any?>?
}
fun isMutableIterable(value: Any?): Boolean = (!(value is kotlin.jvm.internal.markers.KMappedMarker) || value is kotlin.jvm.internal.markers.KMutableIterable) && value is kotlin.collections.Iterable<*>
fun asMutableIterator(value: Any?): kotlin.collections.Iterator<Any?>? {
    if (value is kotlin.jvm.internal.markers.KMappedMarker && !(value is kotlin.jvm.internal.markers.KMutableIterator)) throw ClassCastException("Value cannot be cast to MutableIterator")
    return value as kotlin.collections.Iterator<Any?>?
}
fun isMutableIterator(value: Any?): Boolean = (!(value is kotlin.jvm.internal.markers.KMappedMarker) || value is kotlin.jvm.internal.markers.KMutableIterator) && value is kotlin.collections.Iterator<*>
fun asMutableCollection(value: Any?): kotlin.collections.MutableCollection<Any?>? {
    if (value is kotlin.jvm.internal.markers.KMappedMarker && !(value is kotlin.jvm.internal.markers.KMutableCollection)) throw ClassCastException("Value cannot be cast to MutableCollection")
    return value as kotlin.collections.MutableCollection<Any?>?
}
fun isMutableCollection(value: Any?): Boolean = (!(value is kotlin.jvm.internal.markers.KMappedMarker) || value is kotlin.jvm.internal.markers.KMutableCollection) && value is kotlin.collections.MutableCollection<*>
fun asMutableList(value: Any?): kotlin.collections.MutableList<Any?>? {
    if (value is kotlin.jvm.internal.markers.KMappedMarker && !(value is kotlin.jvm.internal.markers.KMutableList)) throw ClassCastException("Value cannot be cast to MutableList")
    return value as kotlin.collections.MutableList<Any?>?
}
fun isMutableList(value: Any?): Boolean = (!(value is kotlin.jvm.internal.markers.KMappedMarker) || value is kotlin.jvm.internal.markers.KMutableList) && value is kotlin.collections.MutableList<*>
fun asMutableSet(value: Any?): kotlin.collections.MutableSet<Any?>? {
    if (value is kotlin.jvm.internal.markers.KMappedMarker && !(value is kotlin.jvm.internal.markers.KMutableSet)) throw ClassCastException("Value cannot be cast to MutableSet")
    return value as kotlin.collections.MutableSet<Any?>?
}
fun isMutableSet(value: Any?): Boolean = (!(value is kotlin.jvm.internal.markers.KMappedMarker) || value is kotlin.jvm.internal.markers.KMutableSet) && value is kotlin.collections.MutableSet<*>
fun asMutableMap(value: Any?): kotlin.collections.MutableMap<Any?, Any?>? {
    if (value is kotlin.jvm.internal.markers.KMappedMarker && !(value is kotlin.jvm.internal.markers.KMutableMap)) throw ClassCastException("Value cannot be cast to MutableMap")
    return value as kotlin.collections.MutableMap<Any?, Any?>?
}
fun isMutableMap(value: Any?): Boolean = (!(value is kotlin.jvm.internal.markers.KMappedMarker) || value is kotlin.jvm.internal.markers.KMutableMap) && value is kotlin.collections.MutableMap<*, *>
