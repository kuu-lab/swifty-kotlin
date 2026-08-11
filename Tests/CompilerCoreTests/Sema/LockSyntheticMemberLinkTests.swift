#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LockSyntheticMemberLinkTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func externalLinks(
        for owner: String,
        member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlin", "concurrent", owner, member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    // KSP-677: Lock.withLock is migrated to Kotlin source
    // (Stdlib/kotlin/concurrent/Lock.kt) delegating to the demoted
    // __kk_lock_withLock bridge, so it is no longer a synthetic member.

    @Test func testReadWriteLockMembersHaveCorrectExternalLinks() throws {
        let (sema, interner) = try sharedSema()

        let factoryFq = ["kotlin", "concurrent", "readWriteLock"].map { interner.intern($0) }
        let factoryLinks = sema.symbols.lookupAll(fqName: factoryFq).compactMap { sema.symbols.externalLinkName(for: $0) }
        let hasFactory = factoryLinks.contains("kk_read_write_lock_create")
        #expect(hasFactory, "readWriteLock() stub missing")

        let readLinks = externalLinks(for: "ReentrantReadWriteLock", member: "read", sema: sema, interner: interner)
        let hasRead = readLinks.contains("kk_read_write_lock_read")
        #expect(hasRead, "ReentrantReadWriteLock.read() stub missing")

        let writeLinks = externalLinks(for: "ReentrantReadWriteLock", member: "write", sema: sema, interner: interner)
        let hasWrite = writeLinks.contains("kk_read_write_lock_write")
        #expect(hasWrite, "ReentrantReadWriteLock.write() stub missing")
    }
}
#endif
