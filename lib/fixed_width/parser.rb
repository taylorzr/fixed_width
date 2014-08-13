require 'fiber'
require 'stringio'
module FixedWidth
  class Parser
    include Config::API

    options.define(
      definition: { validate: Config::API },
      io: { validate: ->(io) {IO === io || StringIO === io} },
      by: { default: :lines, validate: [:lines, :bytes, :chars] },
      verify_input: { default: true, validate: [true, false] },
      skip_blank: { default: true, validate: [true, false] }
    )
    read_write = [ :definition, :io, :by, :verify_input, :skip_blank ]
    options.configure(
      required: [:definition],
      reader: read_write,
      writer: read_write
    )

    def initialize(opts)
      initialize_options(opts)
      initialize_options(definition.options)
      @input_log = []
      @input_pos = 0
      @should_log_input = false
    end

    def setup(&block)
      opts = {repeat: false, ordered: true}.merge(options.to_hash(true))
      filtered = Section.options.opts.keys.reduce({}) do |acc, key|
        acc[key] = opts[key] if opts.key?(key)
        acc
      end
      root = Section.new(filtered)
      root.setup(&block)
      sections << root
      self
    end

    def parse
      raise ParseError, "IO is not set!" unless options.set?(:io)
      reset_io!
      leftover = nil
      result = sections.map do |section|
        output, leftover = parse_section(section, leftover)
        output
      end.reduce(:merge)
      if verify_input
        leftover ||= advance_io!
        raise UnusedInputError.new %{
          Not all of the input was parsed! Stopped at: #{leftover}
        }.squish if leftover
      end
      result
    end

    private

    def sections
      @sections ||= []
    end

    def parse_section(section, initial_input)
      section.validate!(definition)
      if section.ordered
        parse_in_order(section, initial_input)
      else
        parse_any_order(section, initial_input)
      end
    end

    def parse_any_order(section, input = nil)
      output = {}
      sections_matched = {}
      matcher = make_matcher(section, output)
      left = loop do
        input = advance_io! unless input
        if match = matcher.call(input)
          if match.first.is_a?(Schema)
            schema, opts = match
            singular = preopt(opts, section, :singular)
            add_to_section(output, schema, input, singular)
            input = nil
          else
            sec_out, input, sect = match
            output.merge!(sec_out)
            sections_matched[sect] = true
          end
        else
          missing = section.enum(definition).select { |x|
            case x
            when Section then !x.optional && sections_matched[x]
            when Array
              schema, opts = x
              !preopt(opts, section, :optional) && output[schema.name].blank?
            else raise SectionError.new "Unknown type: #{x.inspect}"
            end
          }
          break input if missing.empty?
          missing = missing.map{ |m| m.is_a?(Section) ? m.schema_names : m.first.name }
          raise RequiredSchemaNotFoundError.new %{
            The following requirements were not met: #{missing.inspect}
            ( could not match from '#{input}' )
          }.squish
        end
      end
      return output, left
    end

    def parse_in_order(section, input = nil)
      output = {}
      parts = make_fiber(section.enum(definition))
      left = loop do
        part = parts.resume unless part
        break input unless part
        if part.is_a?(Section)
          sec_out, input = parse_section(part, input)
          output.merge!(sec_out)
        else
          input = advance_io! unless input
          schema, opts = part
          if schema.match(input)
            singular = preopt(opts, section, :singular)
            add_to_section(output, schema, input, singular)
            part = nil if singular
            input = nil
          elsif !preopt(opts, section, :optional) && output[schema.name].blank?
            raise RequiredSchemaNotFoundError.new %{
              Required schema '#{schema.name}' was not found.
              Last input: '#{input}'
              Intermediate output: #{output.inspect}
            }.squish
          else
            part = nil
          end
        end
      end
      return output, left
    end

    # Parsing Helpers

    def add_to_section(arr, schema, input, singular)
      parsed = schema.parse(input)
      if singular
        raise DuplicateDataError.new %{
          Output of singular schema '#{schema.name}'
          already contains `#{arr[schema.name].inspect}`,
          cannot set to `#{parsed.inspect}`
        }.squish if arr.key?(schema.name)
        arr[schema.name] = parsed
      else
        (arr[schema.name] ||= []) << parsed
      end
    end

    def preopt(hash, obj, key)
      return hash[key] if hash.key?(key)
      obj.opt(key)
    end

    def make_matcher(section, output)
      enum = section.enum(definition)
      subs, schemas = enum.partition{ |x| x.is_a?(Section) }
      lambda { |input|
        found = schemas.detect{ |(s,opts)|
          sing = preopt(opts, section, :singular)
          (!sing || !output.key?(s.name)) && s.match(input)
        }
        return found if found
        subs.each { |sect|
          found = rollback do
            parsed = parse_section(sect, input)
            raise ParseError unless parsed
            parsed
          end
          return found + [sect] if found
        }
        nil
      }
    end

    # Rollback

    def rollback
      befores = [@should_log_input, @input_pos]
      @should_log_input = true
      yield
    rescue ParseError
      @input_pos = befores[1]
      false
    ensure
      @should_log_input = befores[0]
      if !@should_log_input && @input_pos >= @input_log.length
        @input_log.clear
        @input_pos = 0
      end
    end

    # IO Handling

    def reset_io!
      io.rewind
      @input_log = []
      @input_pos = 0
      @line_fiber = nil
    end

    def advance_io!
      if @input_pos < @input_log.length
        @input_pos += 1
        return @input_log[@input_pos - 1]
      end
      next_input = case by
      when :lines then next_line!
      else raise ParseError.new "by(#{by}) is not yet implemented!"
      end
      if @should_log_input
        @input_log << next_input
        @input_pos += 1
      end
      next_input
    end

    def next_line!
      return nil unless line_fiber.alive?
      line = line_fiber.resume.try(:chomp)
      return next_line! if skip_blank && line.blank?
      line
    end

    def line_fiber
      @line_fiber ||= make_fiber(io.each_line)
    end

    def make_fiber(enumerator, terminate = nil)
      Fiber.new do
        enumerator.each do |ele|
          Fiber.yield(ele)
        end
        terminate
      end
    end

  end
end
