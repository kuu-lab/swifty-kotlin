
fun main() {
    // Comprehensive chunked(size, step) and transform tests
    
    println("=== Basic chunked(size) tests ===")
    
    val list = listOf(1, 2, 3, 4, 5, 6, 7)

    // chunked(size) — basic
    println(list.chunked(3))
    println(list.chunked(2))
    println(list.chunked(1))
    println(list.chunked(10))

    // String.chunked (no transform)
    println("abcdefg".chunked(3))
    println("abcdefg".chunked(2))
    
    println("\n=== chunked(size, step) tests ===")
    
    // chunked with step parameter
    val numbers = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    
    // step < size (overlapping chunks)
    println("step 2, size 4: ${numbers.windowed(4, 2, true)}")
    println("step 1, size 3: ${numbers.windowed(3, 1, true)}")
    
    // step == size (non-overlapping)
    println("step 3, size 3: ${numbers.windowed(3, 3, true)}")
    println("step 2, size 2: ${numbers.windowed(2, 2, true)}")
    
    // step > size (gaps between chunks)
    println("step 4, size 2: ${numbers.windowed(2, 4, true)}")
    println("step 5, size 3: ${numbers.windowed(3, 5, true)}")
    
    println("\n=== chunked with transform function ===")
    
    // chunked(size, transform)
    val transformed = list.chunked(3) { chunk ->
        chunk.sum()
    }
    println("chunked(3) sum: $transformed")
    
    val strings = listOf("hello", "world", "kotlin", "test")
    val stringTransformed = strings.chunked(2) { chunk ->
        chunk.joinToString("-")
    }
    println("chunked(2) join: $stringTransformed")
    
    println("\n=== chunked(size, step, transform) tests ===")
    
    // Combine all three parameters
    val complex = numbers.windowed(3, 2, true) { chunk ->
        "chunk(${chunk.joinToString()})=${chunk.average()}"
    }
    println("complex chunked: $complex")
    
    // Different step with transform
    val stepTransform = numbers.windowed(2, 3, true) { chunk ->
        chunk.map { it * it }
    }
    println("step transform: $stepTransform")
    
    println("\n=== String chunked with step ===")
    
    val text = "abcdefghijklmnopqrstuvwxyz"
    
    // String chunked with step
    println("text.windowed(3, 2, true): ${text.windowed(3, 2, true)}")
    println("text.windowed(4, 1, true): ${text.windowed(4, 1, true)}")
    println("text.windowed(5, 5, true): ${text.windowed(5, 5, true)}")
    println("text.windowed(2, 4, true): ${text.windowed(2, 4, true)}")
    
    // String chunked with step and transform
    val stringComplex = text.windowed(3, 2, true) { chunk ->
        chunk.toString().uppercase()
    }
    println("string complex: $stringComplex")
    
    println("\n=== Edge cases ===")
    
    // Empty collections
    println("emptyList.chunked(3): ${emptyList<Int>().chunked(3)}")
    println("emptyList.windowed(3, 2, true): ${emptyList<Int>().windowed(3, 2, true)}")
    println("\"\".chunked(3): ${"".chunked(3)}")
    
    // Single element
    val single = listOf(42)
    println("single.chunked(1): ${single.chunked(1)}")
    println("single.chunked(2): ${single.chunked(2)}")
    println("single.windowed(1, 1, true): ${single.windowed(1, 1, true)}")
    println("single.windowed(1, 2, true): ${single.windowed(1, 2, true)}")
    
    // Size larger than collection
    val small = listOf(1, 2, 3)
    println("small.chunked(5): ${small.chunked(5)}")
    println("small.windowed(5, 3, true): ${small.windowed(5, 3, true)}")
    
    // Step = 1 (maximum overlap)
    println("numbers.windowed(3, 1, true): ${numbers.windowed(3, 1, true)}")
    
    println("\n=== Type-specific tests ===")
    
    // Double list
    val doubles = listOf(1.1, 2.2, 3.3, 4.4, 5.5)
    println("doubles.chunked(2): ${doubles.chunked(2)}")
    println("doubles.windowed(2, 1, true): ${doubles.windowed(2, 1, true)}")
    
    // Character list
    val chars = listOf('a', 'b', 'c', 'd', 'e', 'f')
    println("chars.chunked(2): ${chars.chunked(2)}")
    println("chars.windowed(3, 2, true): ${chars.windowed(3, 2, true)}")
    
    // Boolean list
    val booleans = listOf(true, false, true, false, true)
    println("booleans.chunked(2): ${booleans.chunked(2)}")
    println("booleans.windowed(3, 1, true): ${booleans.windowed(3, 1, true)}")
    
    println("\n=== Complex transform functions ===")
    
    // Transform to different types
    val toStrings = numbers.chunked(3) { chunk ->
        chunk.joinToString("+")
    }
    println("to strings: $toStrings")
    
    val toMaps = numbers.chunked(4) { chunk ->
        chunk.mapIndexed { index, value -> index to value }.toMap()
    }
    println("to maps: $toMaps")
    
    val toBooleans = numbers.chunked(3) { chunk ->
        if (chunk.all { it > 5 }) "true" else "false"
    }
    println("to booleans: $toBooleans")
    
    // Transform with step
    val stepToSum = numbers.windowed(2, 3, true) { chunk ->
        chunk.sum()
    }
    println("step to sum: $stepToSum")
    
    println("\n=== Performance and behavior tests ===")
    
    // Large collection
    val large = (1..100).toList()
    val largeChunked = large.windowed(10, 5, true) { it.size }
    println("large chunked sizes: $largeChunked")
    
    // Verify chunk contents
    val testList = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9)
    val expectedChunks = listOf(listOf(1, 2, 3), listOf(3, 4, 5), listOf(5, 6, 7), listOf(7, 8, 9))
    val actualChunks = testList.windowed(3, 2, true)
    println("expected: $expectedChunks")
    println("actual: $actualChunks")
    println("match: ${expectedChunks == actualChunks}")
    
    println("\n=== Special cases ===")
    
    // Step equal to collection size
    println("numbers.windowed(3, 10, true): ${numbers.windowed(3, 10, true)}")
    
    // Size = 1
    println("numbers.windowed(1, 2, true): ${numbers.windowed(1, 2, true)}")
    println("numbers.windowed(1, 1, true): ${numbers.windowed(1, 1, true)}")
    
    // Transform that returns empty collections
    val emptyTransform = numbers.chunked(3) { emptyList<Int>() }
    println("empty transform: $emptyTransform")
    
    // Transform with side effects (shouldn't affect chunking)
    var counter = 0
    val sideEffectTransform = numbers.chunked(2) { chunk ->
        counter++
        chunk.map { it + counter }
    }
    println("side effect: $sideEffectTransform")
    println("counter: $counter")
}
