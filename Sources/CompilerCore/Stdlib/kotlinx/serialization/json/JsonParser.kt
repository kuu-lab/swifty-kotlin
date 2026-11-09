/*
 * Copyright 2017-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization.json

import kotlinx.serialization.SerializationException

internal class JsonParser(private val source: String) {
    private var offset = 0

    fun parse(): JsonElement {
        skipWhitespace()
        val result = parseValue()
        skipWhitespace()
        if (offset != source.length) fail("Unexpected trailing input")
        return result
    }

    private fun parseValue(): JsonElement {
        skipWhitespace()
        if (offset >= source.length) fail("Unexpected end of input")
        return when (source[offset]) {
            '"' -> JsonPrimitive(parseString())
            '{' -> parseObject()
            '[' -> parseArray()
            't' -> { consume("true"); JsonPrimitive(true) }
            'f' -> { consume("false"); JsonPrimitive(false) }
            'n' -> { consume("null"); JsonNull }
            '-', in '0'..'9' -> parseNumber()
            else -> fail("Unexpected character '${source[offset]}'")
        }
    }

    private fun parseObject(): JsonObject {
        expect('{')
        skipWhitespace()
        val entries = linkedMapOf<String, JsonElement>()
        if (take('}')) return JsonObject(entries)
        while (true) {
            skipWhitespace()
            if (offset >= source.length || source[offset] != '"') fail("Expected an object key")
            val key = parseString()
            skipWhitespace()
            expect(':')
            entries[key] = parseValue()
            skipWhitespace()
            if (take('}')) return JsonObject(entries)
            expect(',')
        }
    }

    private fun parseArray(): JsonArray {
        expect('[')
        skipWhitespace()
        val elements = ArrayList<JsonElement>()
        if (take(']')) return JsonArray(elements)
        while (true) {
            elements += parseValue()
            skipWhitespace()
            if (take(']')) return JsonArray(elements)
            expect(',')
        }
    }

    private fun parseString(): String {
        expect('"')
        val result = StringBuilder()
        while (offset < source.length) {
            val character = source[offset++]
            when (character) {
                '"' -> return result.toString()
                '\\' -> {
                    if (offset >= source.length) fail("Unterminated escape sequence")
                    when (val escaped = source[offset++]) {
                        '"' -> result.append('"')
                        '\\' -> result.append('\\')
                        '/' -> result.append('/')
                        'b' -> result.append('\b')
                        'f' -> result.append('\u000C')
                        'n' -> result.append('\n')
                        'r' -> result.append('\r')
                        't' -> result.append('\t')
                        'u' -> result.append(parseHexCodeUnit())
                        else -> fail("Invalid escape sequence \\$escaped")
                    }
                }
                else -> {
                    if (character.code < 0x20) fail("Unescaped control character")
                    result.append(character)
                }
            }
        }
        fail("Unterminated string")
    }

    private fun parseHexCodeUnit(): Char {
        if (source.length - offset < 4) fail("Incomplete Unicode escape")
        var value = 0
        repeat(4) {
            val digit = source[offset++].digitToIntOrNull(16)
                ?: fail("Invalid Unicode escape")
            value = value * 16 + digit
        }
        return value.toChar()
    }

    private fun parseNumber(): JsonPrimitive {
        val start = offset
        take('-')
        if (!take('0')) {
            if (offset >= source.length || source[offset] !in '1'..'9') fail("Invalid number")
            while (offset < source.length && source[offset] in '0'..'9') offset++
        }
        if (take('.')) {
            if (offset >= source.length || source[offset] !in '0'..'9') fail("Invalid fraction")
            while (offset < source.length && source[offset] in '0'..'9') offset++
        }
        if (offset < source.length && (source[offset] == 'e' || source[offset] == 'E')) {
            offset++
            if (offset < source.length && (source[offset] == '+' || source[offset] == '-')) offset++
            if (offset >= source.length || source[offset] !in '0'..'9') fail("Invalid exponent")
            while (offset < source.length && source[offset] in '0'..'9') offset++
        }
        return JsonLiteral(source.substring(start, offset), isString = false)
    }

    private fun consume(value: String) {
        if (!source.startsWith(value, offset)) fail("Expected '$value'")
        offset += value.length
    }

    private fun expect(character: Char) {
        if (!take(character)) fail("Expected '$character'")
    }

    private fun take(character: Char): Boolean {
        if (offset >= source.length || source[offset] != character) return false
        offset++
        return true
    }

    private fun skipWhitespace() {
        while (offset < source.length && source[offset] in charArrayOf(' ', '\t', '\n', '\r')) offset++
    }

    private fun fail(message: String): Nothing =
        throw SerializationException("Invalid JSON at offset $offset: $message")
}
