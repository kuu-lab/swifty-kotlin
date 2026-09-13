import RuntimeABI

/// FileIO lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
///
/// CLEANUP-STUB-107 removed `java.io.File`'s own Sema facade (constructor,
/// member functions). What remains here are the runtime callee names still
/// produced by the surviving Path/BufferedReader closureRaw-injection and
/// result-tagging logic in `+CallRewriteFile.swift`.
struct FileIOLookupNames {
    let kkBufferedReaderForEachLineName: InternedString
    let kkBufferedReaderUseLinesName: InternedString
    let kkPathUseLinesName: InternedString
    let kkPathUseLinesDefaultName: InternedString
    // STDLIB-IO-PATH-FN-039: Path.walk(options) → kk_path_walk
    let kkPathWalkName: InternedString

    init(interner: StringInterner) {
        kkBufferedReaderForEachLineName = interner.intern("__kk_buffered_reader_forEachLine")
        kkBufferedReaderUseLinesName = interner.intern("__kk_buffered_reader_useLines")
        kkPathUseLinesName = interner.intern("kk_path_useLines")
        kkPathUseLinesDefaultName = interner.intern("kk_path_useLines_default")
        kkPathWalkName = interner.intern("kk_path_walk")
    }
}
