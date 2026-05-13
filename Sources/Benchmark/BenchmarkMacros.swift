@attached(member, names: named(__benchmarkSuites))
@attached(extension, conformances: _BenchmarkDiscovery)
@attached(peer, names: prefixed(__BenchmarkDiscovery_))
public macro BenchmarkSuite(
  _ name: String? = nil,
  _ traits: any BenchmarkSuiteTrait...
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkSuiteMacro")

@attached(peer, names: arbitrary)
public macro Benchmark(
  _ name: String? = nil,
  _ traits: any BenchmarkCaseTrait...
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkMacro")
