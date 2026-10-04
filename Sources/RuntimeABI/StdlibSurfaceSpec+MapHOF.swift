// MARK: - Map higher-order function surface
//
// Split from `StdlibSurfaceSpec.swift` so that parallel branches adding
// `kotlin.collections.Map` member entries do not collide on the same
// central array. New `map(...)` entries go here.

extension StdlibSurfaceSpec {
    // KSP-430: Map higher-order functions are now source-backed in
    // Sources/CompilerCore/Stdlib/kotlin/collections/MapHOF.kt.
    // The runtime bridge entries have been removed, so no map HOF surface
    // specs remain here.
    static let mapHOFMembers: [StdlibSurfaceSpec] = []
}
