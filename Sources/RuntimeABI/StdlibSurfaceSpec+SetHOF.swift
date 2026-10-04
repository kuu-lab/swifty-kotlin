// MARK: - Set higher-order function surface
//
// Split from `StdlibSurfaceSpec.swift` so that parallel branches adding
// `kotlin.collections.Set` member entries do not collide on the same
// central array. New `set(...)` entries go here.

extension StdlibSurfaceSpec {
    // KSP-432: Set higher-order functions are now source-backed in
    // Sources/CompilerCore/Stdlib/kotlin/collections/SetHOF.kt.
    // The runtime bridge entries have been removed, so no set HOF surface
    // specs remain here.
    static let setHOFMembers: [StdlibSurfaceSpec] = []
}
