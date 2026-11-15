package kotlin.jvm.internal.markers
interface KMappedMarker
interface KMutableIterator: KMappedMarker
interface KMutableListIterator: KMutableIterator
interface KMutableIterable: KMappedMarker
interface KMutableCollection: KMutableIterable
interface KMutableList: KMutableCollection
interface KMutableSet: KMutableCollection
interface KMutableMap: KMappedMarker {
    interface Entry: KMappedMarker
}
