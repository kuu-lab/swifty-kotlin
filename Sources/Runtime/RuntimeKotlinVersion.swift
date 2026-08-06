
// KSP-610: `KotlinVersion` itself lives in bundled Kotlin source
// (Sources/CompilerCore/Stdlib/kotlin/KotlinVersion.kt). The only residual native
// bridge is the build-time constant injection of the targeted Kotlin version.
//
// The target version must stay in sync with the rest of the toolchain
// (`kotlinLanguageVersion` in CodegenPhase / LibraryDiscovery, README, CLAUDE.md,
// and `KOTLIN_VERSION` in .github/workflows/ci.yml).
public let kotlinTargetVersion = (major: 2, minor: 3, patch: 10)

/// Returns the targeted Kotlin version packed as `major shl 16 | minor shl 8 | patch`.
@_cdecl("__kk_kotlin_version_current")
public func __kk_kotlin_version_current() -> Int {
    (kotlinTargetVersion.major << 16) | (kotlinTargetVersion.minor << 8) | kotlinTargetVersion.patch
}
