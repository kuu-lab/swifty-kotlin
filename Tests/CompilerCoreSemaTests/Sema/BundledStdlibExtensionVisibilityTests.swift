@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-1447: bundled stdlib `internal` extension properties must not resolve
/// from user code. The extension-property getter/setter recovery fallbacks in
/// `resolveExtensionPropertyGetter` / `resolveExtensionPropertySetter` looked
/// up candidates by short name without applying the `VisibilityChecker` gate
/// that member lookups already enforce.
@Suite
struct BundledStdlibExtensionVisibilityTests {
    @Test(arguments: [false, true])
    func userExtensionPropertySurvivesBundledClassifierImport(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.channels.ChannelResult

        public val ChannelResult<*>.holdsValue: Boolean get() = false

        fun probe(result: ChannelResult<Int>): Boolean = result.holdsValue
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func internalExtensionPropertyReadReportsInvisibleAccess(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.channels.Channel

        fun probe(ch: Channel<Int>): Boolean {
            val result = ch.trySend(1)
            return result.holdsValue
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" },
                    "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func internalExtensionVarWriteReportsInvisibleAccess() throws {
        try withTemporaryFile(contents: """
        import kotlin.native.ref.WeakReference

        @OptIn(ExperimentalNativeApi::class)
        fun probe() {
            val ref = WeakReference(Any())
            ref.pointer = null
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .executable)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" },
                    "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func publicCompanionExtensionPropertyStillResolves(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.channels.Channel

        fun probe(): Int = Channel.CONFLATED
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func sameModuleInternalExtensionPropertyRemainsAccessible() throws {
        try withTemporaryFiles(contents: [
            "internal val String.secretTag: Int get() = length",
            "fun probe(): Int = \"ab\".secretTag",
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .executable)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-4103: `x and 1L` used to bind to kotlinx.io's
    /// `internal infix fun Int.and(other: Long)` through the importless
    /// short-name recovery and reported SEMA-0044. kotlinc reports a plain
    /// argument mismatch against `Int.and(Int)`, so the bundled-internal
    /// candidate must never enter the overload set.
    @Test(arguments: [false, true])
    func bundledInternalBitwiseExtensionDoesNotEnterOverloadSet(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        fun probe(x: Int): Int = x and 1L
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" },
                    "\(ctx.diagnostics.diagnostics)")
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0473" },
                    "\(ctx.diagnostics.diagnostics)")
        }
    }

    /// The same leak produced SEMA-0044 for any bundled-internal extension
    /// whose declared receiver matched (e.g. kotlinx.io's `reverseBytes`).
    /// With no accessible candidate the call is simply unresolved.
    @Test
    func bundledInternalHelperIsUnresolvedNotInvisible() throws {
        try withTemporaryFile(contents: """
        fun probe(x: Int): Int = x.reverseBytes()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .executable)
            try runSema(ctx)
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" },
                    "\(ctx.diagnostics.diagnostics)")
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" },
                    "\(ctx.diagnostics.diagnostics)")
        }
    }

    /// Same-type `Int and Int` — the shape used by generated lexers —
    /// keeps resolving through the primitive member surface.
    @Test(arguments: [false, true])
    func intInfixAndResolvesWithoutBundledInternal(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        fun probe(a: Int, b: Int): Boolean {
            var zzAttributes = a and b
            if (zzAttributes and 1 == 1) {
                zzAttributes = zzAttributes shr 1
            }
            return zzAttributes and 1 == 1
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
