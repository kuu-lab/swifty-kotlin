#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LockSyntheticMemberLinkTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
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

    @Test func testLockWithLockMemberHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "Lock", member: "withLock", sema: sema, interner: interner)
        let hasLink = links.contains("kk_lock_withLock")
        #expect(hasLink, "Lock.withLock() stub missing")
    }

    @Test func testReadWriteLockMembersHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

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
