// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct InstrumentsMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    SpanMacro.self,
    SpanThrowingMacro.self,
    SpanAsyncMacro.self,
    SpanAsyncThrowingMacro.self,
    EventMacro.self,
    SpanAttributeMacro.self,
    InstrumentedBodyMacro.self,
    InstrumentedMembersMacro.self,
  ]
}
