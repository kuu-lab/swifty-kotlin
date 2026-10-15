class Job(val finish: Int, val name: String)

fun sorted(jobs: List<Job>) =
    jobs.sortedWith(Comparator.comparingInt { x: Job -> x.finish })

fun main() {
    val jobs = listOf(
        Job(Int.MAX_VALUE, "max"),
        Job(8, "first-equal"),
        Job(Int.MIN_VALUE, "min"),
        Job(8, "second-equal")
    )
    println(sorted(jobs).map { it.name })

    var selectorCalls = 0
    val comparator = Comparator.comparingInt<Job> { job ->
        selectorCalls += 1
        job.finish
    }
    println(selectorCalls)

    val minimum = Job(Int.MIN_VALUE, "minimum")
    val maximum = Job(Int.MAX_VALUE, "maximum")
    println("${comparator.compare(minimum, maximum)} $selectorCalls")
    println("${comparator.compare(maximum, minimum)} $selectorCalls")

    val equalFirst = Job(42, "equal-first")
    val equalSecond = Job(42, "equal-second")
    println("${comparator.compare(equalFirst, equalSecond)} $selectorCalls")
}
