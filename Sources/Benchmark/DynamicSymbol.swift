// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The address of the global symbol `name` in any image the process has
/// loaded, or `nil` when none defines it.
func dynamicSymbol(_ name: String) -> UnsafeMutableRawPointer? {
  #if canImport(Darwin)
    // RTLD_DEFAULT
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
  #elseif canImport(Glibc)
    dlsym(nil, name)
  #else
    nil
  #endif
}
