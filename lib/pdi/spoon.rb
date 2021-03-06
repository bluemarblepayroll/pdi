# frozen_string_literal: true

#
# Copyright (c) 2020-present, Blue Marble Payroll, LLC
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#

require_relative 'spoon/kitchen_error'
require_relative 'spoon/options'
require_relative 'spoon/pan_error'
require_relative 'spoon/parser'
require_relative 'spoon/result'

module Pdi
  # This class is the main wrapper for PDI's pan and kitchen scripts.
  class Spoon
    DEFAULT_KITCHEN = 'kitchen.sh'
    DEFAULT_PAN     = 'pan.sh'

    TYPES_TO_ERRORS = {
      Options::Type::JOB => KitchenError,
      Options::Type::TRANSFORMATION => PanError
    }.freeze

    attr_reader :args, :dir, :executor, :kitchen, :pan

    def initialize(
      args: [],
      dir:,
      kitchen: DEFAULT_KITCHEN,
      pan: DEFAULT_PAN,
      timeout_in_seconds: nil
    )
      assert_required(:dir, dir)
      assert_required(:kitchen, kitchen)
      assert_required(:pan, pan)

      @args           = Array(args)
      @dir            = File.expand_path(dir.to_s)
      @kitchen        = kitchen.to_s
      @pan            = pan.to_s
      @executor       = Executor.new(timeout_in_seconds: timeout_in_seconds)
      @parser         = Parser.new

      freeze
    end

    # Returns a Spoon::Result instance when PDI returns error code 0 or else raises
    # a KitchenError since Kitchen was used to run the version command.
    def version
      final_args = [kitchen_path] + args + [Options::Arg.new(Options::Arg::Key::VERSION)]

      result       = executor.run(final_args)
      version_line = parser.version(result.out)

      raise(KitchenError, result) if result.code != 0

      Result.new(result, version_line)
    end

    # Returns a <tt>Pdi::Executor::Result</tt> instance when PDI returns error
    # code 0 or else raises a PanError (transformation) or KitchenError (job).
    #
    # An optional block may be passed in so that the output of a run is
    # available in a streaming manner during the run. This block takes one
    # parameter which is the current chunk of output and is called repeatedly
    # throughout the run.
    def run(options, &streaming_reader)
      options  = Options.make(options)
      all_args = run_args(options)

      executor.run(all_args, &streaming_reader).tap do |result|
        raise(error_constant(options), result) if result.code != 0
      end
    end

    private

    attr_reader :parser

    def error_constant(options)
      TYPES_TO_ERRORS.fetch(options.type)
    end

    def run_args(options)
      [script_path(options.type)] + args + options.to_args
    end

    def script_path(options_type)
      if options_type == Options::Type::JOB
        kitchen_path
      elsif options_type == Options::Type::TRANSFORMATION
        pan_path
      end
    end

    def kitchen_path
      File.join(dir, kitchen)
    end

    def pan_path
      File.join(dir, pan)
    end

    def assert_required(name, value)
      raise ArgumentError, "#{name} is required" if value.to_s.empty?
    end
  end
end
