import RuntimeABI

/// FileIO lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
///
/// CLEANUP-STUB-107 removed `java.io.File`'s own Sema facade (constructor,
/// member functions). CLEANUP-STUB-115 removed `kotlin.io.path.Path` entirely.
/// What remains here are the runtime callee names still produced by the
/// surviving BufferedReader closureRaw-injection logic in `+CallRewriteFile.swift`.
struct FileIOLookupNames {
    let kkBufferedReaderForEachLineName: InternedString
    let kkBufferedReaderUseLinesName: InternedString

    init(interner: StringInterner) {
        kkBufferedReaderForEachLineName = interner.intern("__kk_buffered_reader_forEachLine")
        kkBufferedReaderUseLinesName = interner.intern("__kk_buffered_reader_useLines")
    }
}
