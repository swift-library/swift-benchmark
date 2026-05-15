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

@attached(peer, names: arbitrary)
public macro Benchmark<C>(
  _ name: String? = nil,
  _ traits: any BenchmarkCaseTrait...,
  arguments: C
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkMacro")

@attached(peer, names: arbitrary)
public macro Benchmark<C1, C2>(
  _ name: String? = nil,
  _ traits: any BenchmarkCaseTrait...,
  arguments: C1,
  _ collection2: C2
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkMacro")
