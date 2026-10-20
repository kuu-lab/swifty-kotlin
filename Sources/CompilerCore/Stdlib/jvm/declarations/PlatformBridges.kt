package kotlin.jvm.internal
fun <T> __jvmNewList(): kotlin.collections.MutableList<T> = null!!
fun <T> __jvmNewSet(): kotlin.collections.MutableSet<T> = null!!
fun <K, V> __jvmNewMap(): kotlin.collections.MutableMap<K, V> = null!!
fun <K, V> __jvmCopyMap(map: kotlin.collections.Map<out K, V>): kotlin.collections.MutableMap<K, V> = null!!
fun __jvmMapEntries(map: kotlin.collections.Map<*, *>): kotlin.collections.Set<Any> = null!!
fun __jvmMapEntryKey(entry: Any): Any? = null
fun __jvmMapEntryValue(entry: Any): Any? = null
fun <K, V> __jvmPutAllMap(destination: kotlin.collections.MutableMap<K, V>, source: kotlin.collections.Map<out K, V>) {}
fun <T> __jvmEmptyList(): kotlin.collections.List<T> = null!!
fun <T> __jvmEmptySet(): kotlin.collections.Set<T> = null!!
fun <K, V> __jvmEmptyMap(): kotlin.collections.Map<K, V> = null!!
fun <T> __jvmSingletonList(element: T): kotlin.collections.List<T> = null!!
fun <T> __jvmSingletonSet(element: T): kotlin.collections.Set<T> = null!!
fun <K, V> __jvmSingletonMap(key: K, value: V): kotlin.collections.Map<K, V> = null!!
fun <T> __jvmArrayList(elements: kotlin.Array<out T>): kotlin.collections.List<T> = null!!
fun __jvmPrint(value: Any?) {}
fun __jvmPrintln(value: Any?) {}
fun __jvmNewline() {}

fun __jvmWhitespace(value: Char): Boolean = false
fun __jvmSpaceChar(value: Char): Boolean = false
fun __jvmSubstring(value: String, start: Int, end: Int): String = null!!
fun __jvmRootLocale(): Any = null!!
fun __jvmUppercase(value: String, locale: Any): String = null!!
fun __jvmLowercase(value: String, locale: Any): String = null!!
fun __jvmEqualsIgnoreCase(value: String, other: String?): Boolean = false
fun __jvmParseByte(value: String, radix: Int): Byte = null!!
fun __jvmParseShort(value: String, radix: Int): Short = null!!
fun __jvmParseInt(value: String, radix: Int): Int = null!!
fun __jvmParseLong(value: String, radix: Int): Long = null!!
fun __jvmParseFloat(value: String): Float = null!!
fun __jvmParseDouble(value: String): Double = null!!
fun __jvmUpperChar(value: Char): Char = null!!
fun __jvmLowerChar(value: Char): Char = null!!
fun __jvmIndexOf(value: String, needle: String, start: Int): Int = 0
fun __jvmLastIndexOf(value: String, needle: String, start: Int): Int = 0
fun <T> __jvmSortList(list: kotlin.collections.MutableList<T>) {}
fun __jvmReverseOrder(): Any = null!!
fun <T> __jvmSortListWithComparator(list: kotlin.collections.MutableList<T>, comparator: Any) {}
fun <T> __jvmCopyList(collection: kotlin.collections.Collection<T>): kotlin.collections.MutableList<T> = null!!
fun __jvmAtomicFlag(): Any = null!!
fun __jvmCompareFlag(flag: Any, expected: Boolean, value: Boolean): Boolean = false
fun __jvmMinDouble(first: Double, second: Double): Double = 0.0
fun __jvmMaxDouble(first: Double, second: Double): Double = 0.0
fun __jvmMinFloat(first: Float, second: Float): Float = 0.0f
fun __jvmMaxFloat(first: Float, second: Float): Float = 0.0f
fun __jvmClassOf(value: Any): Any = null!!
fun __jvmGenericInterfaces(type: Any): Array<Any> = null!!
fun __jvmAtomicReference(value: Any?): Any = null!!
fun __jvmAtomicGet(state: Any): Any? = null
fun __jvmAtomicCAS(state: Any, expected: Any?, value: Any?): Boolean = false
fun __jvmResume(continuation: kotlin.coroutines.Continuation<*>, value: Any?) {}
fun __jvmLatch(count: Int = 1): Any = null!!
fun __jvmCountDown(latch: Any) {}
fun __jvmAwait(latch: Any) {}
fun <T> __jvmResultValue(result: kotlin.Result<T>): Any? = null
fun __jvmLock(): Any = null!!
fun __jvmLockAcquire(lock: Any) {}
fun __jvmLockRelease(lock: Any) {}
fun __jvmAtomicSet(state: Any, value: Any?) {}
fun __jvmPattern(pattern: String, flags: Int): Any = null!!
fun __jvmPatternQuote(text: String): String = null!!
fun __jvmMatcherQuote(text: String): String = null!!
fun __jvmPatternText(pattern: Any): String = null!!
fun __jvmPatternFlags(pattern: Any): Int = 0
fun __jvmMatcher(pattern: Any, input: CharSequence): Any = null!!
fun __jvmMatcherMatches(matcher: Any): Boolean = false
fun __jvmMatcherFind(matcher: Any): Boolean = false
fun __jvmMatcherFindAt(matcher: Any,index: Int): Boolean = false
fun __jvmMatcherLookingAt(matcher: Any): Boolean = false
fun __jvmMatcherRegion(matcher: Any,start: Int, end: Int): Any = null!!
fun __jvmMatcherTransparent(matcher: Any,value: Boolean): Any = null!!
fun __jvmMatcherAnchoring(matcher: Any,value: Boolean): Any = null!!
fun __jvmMatcherReplaceAll(matcher: Any,replacement: String): String = null!!
fun __jvmMatcherReplaceFirst(matcher: Any,replacement: String): String = null!!
fun __jvmMatcherGroupCount(matcher: Any): Int = 0
fun __jvmMatcherGroup(matcher: Any,index: Int): String? = null
fun __jvmMatcherStart(matcher: Any,index: Int): Int = 0
fun __jvmMatcherEnd(matcher: Any,index: Int): Int = 0
fun __jvmMatcherGroupNamed(matcher: Any,name: String): String? = null
fun __jvmMatcherStartNamed(matcher: Any,name: String): Int = 0
fun __jvmMatcherEndNamed(matcher: Any,name: String): Int = 0
fun __jvmUIntString(value: Int): String = null!!
fun __jvmULongString(value: Long): String = null!!
fun __jvmUIntCompare(first: Int, second: Int): Int = 0
fun __jvmULongCompare(first: Long, second: Long): Int = 0
fun __jvmMonitorEnter(lock: Any) {}
fun __jvmMonitorExit(lock: Any) {}
fun __jvmClassName(type: Any): String = null!!
fun __jvmClassSimpleName(type: Any): String = null!!
fun __jvmClassModifiers(type: Any): Int = 0
fun __jvmDeclaredMethods(type: Any): Array<Any> = null!!
fun __jvmPublicMethods(type: Any): Array<Any> = null!!
fun __jvmDeclaredConstructors(type: Any): Array<Any> = null!!
fun __jvmDeclaredClasses(type: Any): Array<Any> = null!!
fun __jvmDeclaredFields(type: Any): Array<Any> = null!!
fun __jvmClassLoader(type: Any): Any? = null
fun __jvmClassSuperclass(type: Any): Any? = null
fun __jvmClassInterfaces(type: Any): Array<Any> = null!!
fun __jvmClassIsAnnotation(type: Any): Boolean = false
fun __jvmClassIsPrimitive(type: Any): Boolean = false
fun __jvmClassIsArray(type: Any): Boolean = false
fun __jvmClassIsLocal(type: Any): Boolean = false
fun __jvmClassIsAnonymous(type: Any): Boolean = false
fun __jvmClassInstance(type: Any, value: Any?): Boolean = false
fun __jvmLoadClass(name: String, initialize: Boolean, loader: Any?): Any = null!!
fun __jvmClassAnnotation(type: Any, annotationType: Any): Annotation? = null
fun __jvmAnnotations(element: Any): Array<Annotation> = null!!
fun __jvmAnnotationsByType(element: Any, type: Any): Array<Annotation> = null!!
fun __jvmMethodName(method: Any): String = null!!
fun __jvmMethodReturn(method: Any): Any = null!!
fun __jvmMethodDefault(method: Any): Any? = null
fun __jvmMethodInvoke(method: Any, receiver: Any?, arguments: Array<Any?>): Any? = null
fun __jvmExecutableParams(method: Any): Array<Any> = null!!
fun __jvmExecutableParamAnnotations(method: Any): Array<Array<Annotation>> = null!!
fun __jvmExecutableModifiers(method: Any): Int = 0
fun __jvmExecutableSynthetic(method: Any): Boolean = false
fun __jvmConstructorInvoke(constructor: Any, arguments: Array<Any?>): Any = null!!
fun __jvmSetAccessible(element: Any, accessible: Boolean): Unit {}
fun __jvmInvocationCause(exception: Any): Throwable? = null
fun __jvmFieldName(field: Any): String = null!!
fun __jvmFieldGet(field: Any, receiver: Any?): Any? = null
fun __jvmFieldSet(field: Any, receiver: Any?, value: Any?): Unit {}
fun __jvmFieldModifiers(field: Any): Int = 0
fun __jvmRepeatableContainer(annotation: Any): Any = null!!
fun __jvmAnnotationType(annotation: Annotation): Any = null!!
fun __jvmComponentType(type: Any): Any = null!!
fun __jvmNewStackTraceElement(type: String, method: String, file: String, line: Int): java.lang.StackTraceElement = null!!
fun __jvmProxy(loader: Any?, types: Array<java.lang.Class<*>>, handler: java.lang.reflect.InvocationHandler): Any = null!!
fun __jvmDeepEquals(first: Any?, second: Any?): Boolean = false
fun __jvmDeepHash(values: Array<Any?>): Int = 0
fun __jvmDeepString(values: Array<Any?>): String = null!!
fun <T> __jvmCopyArray(array: Array<T>, size: Int): Array<T> = null!!
fun __jvmUtf8String(bytes: ByteArray, charset: String): String = null!!
fun <T> __jvmUnmodifiableSet(value: Set<T>): Set<T> = null!!
fun __jvmUIntDivide(first: Int, second: Int): Int = 0
fun __jvmUIntRemainder(first: Int, second: Int): Int = 0
fun __jvmULongDivide(first: Long, second: Long): Long = 0
fun __jvmULongRemainder(first: Long, second: Long): Long = 0
fun __jvmULongStringRadix(value: Long, radix: Int): String = null!!
fun <E: Enum<E>> __jvmEnumEntries(entries: Array<E>): kotlin.enums.EnumEntries<E> = null!!
fun __jvmArrayCopy(source: Any?, sourceIndex: Int, target: Any?, targetIndex: Int, count: Int) {}

fun <T> __jvmNewArrayList(): java.util.ArrayList<T> = null!!

fun __jvmRemoveAllCollection(destination: kotlin.collections.Collection<*>, source: kotlin.collections.Collection<*>): Boolean = null!!
fun <T> __jvmCopySet(collection: kotlin.collections.Collection<T>): kotlin.collections.MutableSet<T> = null!!
