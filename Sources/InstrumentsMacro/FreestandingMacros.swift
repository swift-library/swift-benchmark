// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import SwiftSyntax
import SwiftSyntaxMacros

public struct SpanMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "")
  }
}

public struct SpanThrowingMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "try ")
  }
}

public struct SpanAsyncMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "await ")
  }
}

public struct SpanAsyncThrowingMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "try await ")
  }
}

public struct EventMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeEventExpression(from: node)
  }
}
