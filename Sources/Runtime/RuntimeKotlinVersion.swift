
// Kotlin language version targeted by this compiler build (see CLAUDE.md).
// `kotlin.KotlinVersion` itself lives in bundled Kotlin source; the runtime only
// injects this build-time constant.
private let currentKotlinVersion = (major: 2, minor: 3, patch: 10)

@_cdecl("__kk_kotlin_version_current")
public func __kk_kotlin_version_current() -> Int {
    currentKotlinVersion.major * 65536 + currentKotlinVersion.minor * 256 + currentKotlinVersion.patch
}
