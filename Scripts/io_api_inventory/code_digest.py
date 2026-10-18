"""Comment-insensitive content digest for local Swift and Kotlin sources.

The source catalog pins local implementation files by content. A plain SHA-256 of
the bytes also changes when only a comment is edited, which forced a catalog
refresh (and a Kotlin 2.3.10 PSI run) for pure documentation changes. The digest
here hashes the code with comments removed, so comment-only edits keep it stable
while any change to code or to a string literal still changes it.
"""

import hashlib

DIGEST_ALGORITHM = "code-sha256-v1"


def strip_comments(source: str, language: str) -> str:
    """Remove ``//`` and ``/* */`` comments, leaving string and character literals intact."""
    if language not in ("swift", "kt"):
        raise ValueError("unsupported language: " + language)
    output = []
    index, length = 0, len(source)
    while index < length:
        char = source[index]
        following = source[index + 1] if index + 1 < length else ""
        if char == "/" and following == "/":
            while index < length and source[index] != "\n":
                index += 1
            continue
        if char == "/" and following == "*":
            depth = 1
            index += 2
            while index < length and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            output.append(" ")
            continue
        if language == "swift" and char in '#"':
            cursor, hashes = index, 0
            while cursor < length and source[cursor] == "#":
                hashes += 1
                cursor += 1
            if cursor < length and source[cursor] == '"':
                quote = '"""' if source.startswith('"""', cursor) else '"'
                end_marker = quote + "#" * hashes
                scan = cursor + len(quote)
                while scan < length:
                    if source[scan] == "\\" and hashes == 0:
                        scan += 2
                        continue
                    if source.startswith(end_marker, scan):
                        scan += len(end_marker)
                        break
                    scan += 1
                output.append(source[index:scan])
                index = scan
                continue
            output.append(char)
            index += 1
            continue
        if language == "kt" and char == '"':
            quote = '"""' if source.startswith('"""', index) else '"'
            scan = index + len(quote)
            while scan < length:
                if source[scan] == "\\" and quote == '"':
                    scan += 2
                    continue
                if source.startswith(quote, scan):
                    scan += len(quote)
                    break
                scan += 1
            output.append(source[index:scan])
            index = scan
            continue
        if language == "kt" and char == "'":
            scan = index + 1
            while scan < length:
                if source[scan] == "\\":
                    scan += 2
                    continue
                if source[scan] == "'":
                    scan += 1
                    break
                scan += 1
            output.append(source[index:scan])
            index = scan
            continue
        output.append(char)
        index += 1
    return "".join(output)


def code_sha256(data: bytes, language: str) -> str:
    """SHA-256 of the code with comments removed and whitespace runs collapsed to one space.

    Whitespace is collapsed rather than deleted because the presence of a space
    between tokens is significant (``= @convention`` is not ``=@convention``);
    collapsing only discards the layout that a deleted comment line leaves behind.
    """
    code = " ".join(strip_comments(data.decode("utf-8"), language).split())
    return hashlib.sha256(code.encode("utf-8")).hexdigest()
