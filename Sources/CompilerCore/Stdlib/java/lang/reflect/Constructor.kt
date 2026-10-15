package java.lang.reflect

import kotlin.reflect.KCallable

/** Native Java-constructor handles use the runtime's KCallable representation. */
public typealias Constructor<T> = KCallable<T>
