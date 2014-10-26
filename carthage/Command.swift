//
//  Command.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit

/// Represents a Carthage subcommand that can be executed with its own set of
/// arguments.
public protocol CommandType {
	/// The action that users should specify to use this subcommand (e.g.,
	/// `help`).
	var verb: String { get }

	/// Runs this subcommand in the given mode.
	func run(mode: CommandMode) -> Result<()>
}

/// Describes the "mode" in which a command should run.
public enum CommandMode {
	/// Options should be parsed from the given command-line arguments.
	case Arguments([String])

	/// Each option should record its usage information in an error, for
	/// presentation to the user.
	case Usage
}

/// Represents a record of options for a command, which can be parsed from
/// a list of command-line arguments.
///
/// This is most helpful when used in conjunction with the `option` function,
/// and `<*>` and `<|` combinators.
///
/// Example:
///
///		struct LogOptions: OptionsType {
///			let verbosity: Int
///			let outputFilename: String?
///			let logName: String
///
///			static func create(verbosity: Int)(outputFilename: String?)(logName: String) -> LogOptions {
///				return LogOptions(verbosity: verbosity, outputFilename: outputFilename, logName: logName)
///			}
///
///			static func evaluate(m: CommandMode) -> Result<LogOptions> {
///				return create
///					<*> m <| option("verbose", 0, "The verbosity level with which to read the logs")
///					<*> m <| option("outputFilename", "A file to print output to, instead of stdout")
///					<*> m <| option("logName", "all", "The log to read")
///			}
///		}
public protocol OptionsType {
	/// Evaluates this set of options in the given mode.
	///
	/// Returns the parsed options, or an `InvalidArgument` error containing
	/// usage information.
	class func evaluate(m: CommandMode) -> Result<Self>
}

/// Describes an option that can be provided on the command line.
public struct Option<T> {
	/// The key that controls this option.
	///
	/// For example, a key of `verbose` would be used for a `--verbose` option.
	public let key: String

	/// The default value for this option. This is the value that will be used
	/// if the option is never explicitly specified on the command line.
	public let defaultValue: T

	/// A human-readable string describing the purpose of this option. This will
	/// be shown in help messages.
	public let usage: String
}

extension Option: Printable {
	public var description: String {
		return "--\(key)"
	}
}

/// Constructs an option with the given parameters.
public func option<T: ArgumentType>(key: String, defaultValue: T, usage: String) -> Option<T> {
	return Option(key: key, defaultValue: defaultValue, usage: usage)
}

/// Contructs a nullable option with the given parameters.
///
/// This must be used for options that permit `nil`, because it's impossible to
/// extend `Optional` with the `ArgumentType` protocol.
public func option<T: ArgumentType>(key: String, usage: String) -> Option<T?> {
	return Option(key: key, defaultValue: nil, usage: usage)
}

/// Represents a value that can be converted from a command-line argument.
public protocol ArgumentType {
	/// Attempts to parse a value from the given command-line argument.
	class func fromString(string: String) -> Self?
}

extension Int: ArgumentType {
	public static func fromString(string: String) -> Int? {
		return string.toInt()
	}
}

extension String: ArgumentType {
	public static func fromString(string: String) -> String? {
		return string
	}
}

/// Constructs an `InvalidArgument` error that describes how to use `option`.
private func informativeUsageError<T>(option: Option<T>) -> NSError {
	let description = "\(option)\n\t\(option.usage)"
	return CarthageError.InvalidArgument(description: description).error
}

/// Constructs an `InvalidArgument` error that describes how `option` was used
/// incorrectly.
///
/// If provided, `value` should be the invalid value given by the user.
private func invalidUsageError<T>(option: Option<T>, value: String?) -> NSError {
	var description: String?
	if let value = value {
		description = "Invalid value for \(option): \(value)"
	} else {
		description = "Missing argument for \(option)"
	}

	return CarthageError.InvalidArgument(description: description!).error
}

/// Implements <| uniformly over all values, even those that may not necessarily
/// conform to ArgumentType.
private func evaluateOption<T>(option: Option<T>, defaultValue: T, mode: CommandMode, parse: String -> T?) -> Result<T> {
	switch (mode) {
	case let .Arguments(arguments):
		var keyIndex = find(arguments, "--\(option.key)")
		if let keyIndex = keyIndex {
			if keyIndex + 1 < arguments.count {
				let stringValue = arguments[keyIndex + 1]
				if let value = parse(stringValue) {
					return success(value)
				} else {
					return failure(invalidUsageError(option, stringValue))
				}
			}

			return failure(invalidUsageError(option, nil))
		}

		return success(defaultValue)

	case .Usage:
		return failure(informativeUsageError(option))
	}
}

/// Combines the text of the two errors, if they're both `InvalidArgument`
/// errors. Otherwise, uses whichever one is not (biased toward the left).
private func combineUsageErrors(left: NSError, right: NSError) -> NSError {
	let combinedError = CarthageError.InvalidArgument(description: "\(left.localizedDescription)\n\(right.localizedDescription)").error

	func isUsageError(error: NSError) -> Bool {
		return error.domain == combinedError.domain && error.code == combinedError.code
	}

	if isUsageError(left) {
		if isUsageError(right) {
			return combinedError
		} else {
			return right
		}
	} else {
		return left
	}
}

// Inspired by the Argo library:
// https://github.com/thoughtbot/Argo
/*
	Copyright (c) 2014 thoughtbot, inc.

	MIT License

	Permission is hereby granted, free of charge, to any person obtaining
	a copy of this software and associated documentation files (the
	"Software"), to deal in the Software without restriction, including
	without limitation the rights to use, copy, modify, merge, publish,
	distribute, sublicense, and/or sell copies of the Software, and to
	permit persons to whom the Software is furnished to do so, subject to
	the following conditions:

	The above copyright notice and this permission notice shall be
	included in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
	LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
	OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
	WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
infix operator <*> {
	associativity left
}

infix operator <| {
	associativity left
	precedence 150
}

/// Applies `f` to the value in the given result.
///
/// In the context of command-line option parsing, this is used to chain
/// together the parsing of multiple arguments. See OptionsType for an example.
public func <*><T, U>(f: T -> U, value: Result<T>) -> Result<U> {
	return value.map(f)
}

/// Applies the function in `f` to the value in the given result.
///
/// In the context of command-line option parsing, this is used to chain
/// together the parsing of multiple arguments. See OptionsType for an example.
public func <*><T, U>(f: Result<(T -> U)>, value: Result<T>) -> Result<U> {
	switch (f, value) {
	case let (.Failure(left), .Failure(right)):
		return failure(combineUsageErrors(left, right))

	case let (.Failure(left), .Success):
		return failure(left)

	case let (.Success, .Failure(right)):
		return failure(right)

	case let (.Success(f), .Success(value)):
		let newValue = f.unbox(value.unbox)
		return success(newValue)
	}
}

/// Evaluates the given option in the given mode.
///
/// If parsing command line arguments, and no value was specified on the command
/// line, the option's `defaultValue` is used.
public func <|<T: ArgumentType>(mode: CommandMode, option: Option<T>) -> Result<T> {
	return evaluateOption(option, option.defaultValue, mode) { str in T.fromString(str) }
}

/// Evaluates the given nullable option in the given mode.
///
/// If parsing command line arguments, and no value was specified on the command
/// line, `nil` is used.
public func <|<T: ArgumentType>(mode: CommandMode, option: Option<T?>) -> Result<T?> {
	return evaluateOption(option, option.defaultValue, mode) { str in T.fromString(str) }
}
