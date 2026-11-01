package java.util.concurrent

import java.util.NavigableMap

// KUU-4118: java.util.concurrent.ConcurrentNavigableMap — ConcurrentMap's
// atomic conditional-update contract over a NavigableMap, implemented by
// ConcurrentSkipListMap. The JVM interface additionally narrows the
// subMap/headMap/tailMap/descendingMap view return types to
// ConcurrentNavigableMap and declares navigableKeySet; the bundled surface
// keeps the inherited NavigableMap signatures — the runtime view boxes are
// tagged NavigableMap, and single-threaded execution cannot observe the
// stronger view guarantees anyway.
public interface ConcurrentNavigableMap<K, V> : ConcurrentMap<K, V>, NavigableMap<K, V>
