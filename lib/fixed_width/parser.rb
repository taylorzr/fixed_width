require 'fiber'
module FixedWidth
  class Parser

    def initialize(definition, io)
      @definition = definition
      @io         = io
    end

    def parse(opts = {})
      opts = { in_order: true }.merge(opts)
      reset_io!
      if opts[:in_order]
        parse_in_order(opts)
      else
        parse_any_order(opts)
      end
    end

    def parse_any_order(opts = {})
      opts = {
        raise_on_failure: false,
        save_unparsable: true,
        verify_sections: true
      }.merge(opts)
      @parsed = {}
      line_number = 0
      failed = []
      while(line = next_line!) do
        section = @definition.sections.detect{ |s| s.match(line) }
        if section
          add_to_section(section, line)
        elsif opts[:raise_on_failure]
          failed << [line_number, line]
        elsif opts[:save_unparsable]
          @parsed[:__unparsable] ||= []
          @parsed[:__unparsable] << [line_number, line]
        end
        line_number += 1
      end
      if opts[:raise_on_failure] && !failed.empty?
        lines = failed.map { |ind, line| "\n#{ind+1}: #{line}" }
        raise FixedWidth::UnusedLineError.new(
          "Could not match the following lines:#{lines}")
      end
      if opts[:verify_sections]
        missing = @definition.sections.select? { |sec|
          !@parsed[sec.name] && !sec.optional
        }.map(&:name)
        unless missing.empty?
          raise FixedWidth::RequiredSectionNotFoundError.new(
            "The following required sections were not found: " +
              "#{missing.inspect}")
        end
      end
      @parsed
    end

    def parse_in_order(opts = {})
      @parsed = {}
      @definition.sections.each do |section|
        if (line = next_line!) && section.match(line)
          add_to_section(section, line)
        elsif !section.optional
          raise FixedWidth::RequiredSectionNotFoundError.new(
            "Required section '#{section.name}' was not found.")
        end
      end
      @parsed
    end

    private

    def add_to_section(section, line)
      if section.singular
        @parsed[section.name] = section.parse(line)
      else
        @parsed[section.name] ||= []
        @parsed[section.name] << section.parse(line)
      end
    end

    def line_fiber
      @line_fiber ||= Fiber.new do
        @io.each_line do |line|
          Fiber.yield(line)
        end
        nil
      end
    end

    def reset_io!
      @io.rewind
      @line_fiber = nil
    end

    def next_line!
      line_fiber.alive? ? line_fiber.resume.try(:chomp) : nil
    end

  end
end
