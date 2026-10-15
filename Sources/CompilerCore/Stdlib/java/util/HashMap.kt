/*
 * KUU-2234: expose Kotlin's native-backed HashMap through the JVM FQN.
 */

package java.util

public typealias HashMap<K, V> = kotlin.collections.HashMap<K, V>
