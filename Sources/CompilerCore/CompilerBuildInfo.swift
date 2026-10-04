/// Shared identifier for this compiler build. Artifact caches (the stdlib
/// artifact cache and the incremental compilation cache) fold it into their
/// identity so artifacts produced by a different toolchain never collide.
public enum CompilerBuildInfo {
    public static let version = "0.1.0"
}
