/*
 * KUU-1857: expose the native-backed Kotlin ArrayList through the JVM FQN.
 */

package java.util

public typealias ArrayList<E> = kotlin.collections.ArrayList<E>
