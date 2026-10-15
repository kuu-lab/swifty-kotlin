/*
 * KUU-2225: expose kotlin.Comparator through the JVM java.util FQN.
 */

package java.util

public typealias Comparator<T> = kotlin.Comparator<T>
