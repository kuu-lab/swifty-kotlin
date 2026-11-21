
struct FileIOLookupNames {
    let kkBufferedReaderForEachLineName: InternedString
    let kkBufferedReaderUseLinesName: InternedString

    init(interner: StringInterner) {
        kkBufferedReaderForEachLineName = interner.intern("__kk_buffered_reader_forEachLine")
        kkBufferedReaderUseLinesName = interner.intern("__kk_buffered_reader_useLines")
    }
}
