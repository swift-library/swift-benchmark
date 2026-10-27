// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

@attached(member, names: named(__benchmarkSuites))
@attached(extension, conformances: _BenchmarkDiscovery)
@attached(peer, names: prefixed(__BenchmarkDiscovery_))
public macro BenchmarkSuite(
  _ name: String? = nil,
  _ traits: any BenchmarkSuiteTrait...
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkSuiteMacro")

@attached(peer)
public macro Benchmark(
  _ name: String? = nil,
  _ traits: any BenchmarkCaseTrait...
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkMacro")

/// Declares a benchmark whose every call takes a fresh input from `setup`:
/// the method takes one `inout` parameter, and `setup` makes its value, from
/// the row's size when the benchmark has a `.dimension` trait. Neither `setup`
/// nor freeing the input is timed or counted.
@attached(peer)
public macro Benchmark<Setup>(
  _ name: String? = nil,
  _ traits: any BenchmarkCaseTrait...,
  setup: Setup
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkMacro")

@attached(peer)
public macro Benchmark<C>(
  _ name: String? = nil,
  _ traits: any BenchmarkCaseTrait...,
  arguments: C
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkMacro")

@attached(peer)
public macro Benchmark<C1, C2>(
  _ name: String? = nil,
  _ traits: any BenchmarkCaseTrait...,
  arguments: C1,
  _ collection2: C2
) = #externalMacro(module: "BenchmarkMacro", type: "BenchmarkMacro")
