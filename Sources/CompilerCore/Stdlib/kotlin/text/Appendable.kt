/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib common Appendable declarations.
 */

package kotlin.text

import kotlin.internal.KsSymbolName

/**
 * The append contract shared by StringBuilder and other mutable character
 * sinks. The runtime links are retained because StringBuilder is backed by a
 * runtime handle and does not populate ordinary object itable entries.
 */
public interface Appendable {
    @KsSymbolName("__kk_string_builder_append_char")
    public external fun append(value: Char): Appendable

    @KsSymbolName("__kk_string_builder_append_obj")
    public external fun append(value: CharSequence?): Appendable

    @KsSymbolName("__kk_string_builder_append_range")
    public external fun append(value: CharSequence?, startIndex: Int, endIndex: Int): Appendable
}
