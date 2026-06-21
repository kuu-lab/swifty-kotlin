extension ABILoweringPass {
    /// Sequence non-throwing callees: creation, transformation, terminal operations.
    static func nonThrowingSequenceCallees(_ interner: StringInterner) -> [InternedString] {
        [
            // Sequence (STDLIB-003) — these are non-throwing extern C functions.
            interner.intern("kk_sequence_from_list"),
            interner.intern("kk_sequence_map"),
            interner.intern("kk_sequence_filter"),
            interner.intern("kk_sequence_take"),
            interner.intern("kk_sequence_constrainOnce"),
            interner.intern("kk_sequence_builder_create"),
            interner.intern("kk_sequence_builder_yield"),
            interner.intern("kk_sequence_builder_build"),
            interner.intern("kk_iterator_builder_build"),
            // Sequence (STDLIB-095/096/097)
            interner.intern("kk_sequence_of"),
            interner.intern("kk_sequence_of_single"),
            interner.intern("kk_sequence_generate"),
            interner.intern("kk_sequence_generate_noarg"),
            interner.intern("kk_sequence_forEach"),
            interner.intern("kk_sequence_flatMap"),
            interner.intern("kk_sequence_flatMapIndexed"),
            interner.intern("kk_sequence_intersect"),
            interner.intern("kk_sequence_drop"),
            interner.intern("kk_sequence_distinct"),
            interner.intern("kk_sequence_zip"),
            interner.intern("kk_sequence_sorted"),
            interner.intern("kk_sequence_sortedDescending"),
            interner.intern("kk_sequence_filterIsInstance"),
            interner.intern("kk_sequence_filterNotNull"),
            interner.intern("kk_sequence_requireNoNulls"),
            interner.intern("kk_sequence_reversed"),
            interner.intern("kk_sequence_withIndex"),
            interner.intern("kk_sequence_joinTo"),
            interner.intern("kk_sequence_joinToString"),
            interner.intern("kk_sequence_indexOf"),
            interner.intern("kk_sequence_lastIndexOf"),
            interner.intern("kk_sequence_chunked"),
            interner.intern("kk_sequence_windowed"),
            interner.intern("kk_empty_sequence"),
            interner.intern("kk_sequence_orEmpty"),
            // NOTE: kk_sequence_firstOrNull and kk_sequence_count are NOT
            // non-throwing — they accept an outThrown parameter for lazy
            // pipeline exception propagation.
            interner.intern("kk_sequence_forEachIndexed"),
            interner.intern("kk_sequence_zipWithNext"),
            // Sequence (STDLIB-470)
            interner.intern("kk_sequence_toSet"),
            interner.intern("kk_sequence_toSortedSet"),
            interner.intern("kk_sequence_toHashSet"),
            interner.intern("kk_sequence_toMap"),
            interner.intern("kk_sequence_toCollection"),
            interner.intern("kk_sequence_maxOrNull"),
            interner.intern("kk_sequence_minOrNull"),
            interner.intern("kk_sequence_flatten"),
            // Sequence plus/minus (STDLIB-561/562)
            interner.intern("kk_sequence_plus"),
            interner.intern("kk_sequence_plus_element"),
            interner.intern("kk_sequence_minus"),
            interner.intern("kk_sequence_union"),
            interner.intern("kk_sequence_subtract"),
            interner.intern("kk_sequence_filterIsInstanceTo"),
            interner.intern("kk_sequence_shuffled"),
            interner.intern("kk_sequence_shuffled_random"),
        ]
    }
}
