class FixedWidth
  class Parser
    def initialize(definition, file)
      @definition = definition
      @file       = file
    end

    def parse(by_section=true)
      if by_section
        parse_by_section
      else
        parse_by_line
      end
    end

    # Try to match each line with a section
    def parse_by_line(raise_on_failure=false, save_unparsable=true)
      @parsed = {}
      @lines = read_file

      return @parsed if @lines.empty?

      result = @lines.map.with_index do |line, index|
        if section = @definition.sections.detect{|s| s.match(line)}
          add_to_section(section, line)
          [section, line, index]
        else
          [nil, line, index]
        end
      end

      @failed = result.reject{|section, _, _| section}

      if raise_on_failure && @failed.any?
        messages = @failed.map do |_, line, index|
          "couldn't parse line #{index + 1}: #{line.inspect}"
        end

        raise "Unparsable file: #{messages.join(', ')}"
      end

      if save_unparsable && @failed.any?
        @parsed[:__unparsable] = @failed.map{|_, line, index| [index, line]}
      end

      @parsed
    end

    # Try to fulfill all sections
    def parse_by_section
      @parsed = {}
      @lines = read_file

      return @parsed if @lines.empty?

      @definition.sections.each do |section|
        rows = fill_content(section)
        raise FixedWidth::RequiredSectionNotFoundError.new("Required section '#{section.name}' was not found.") unless rows > 0 || section.optional
      end

      @parsed
    end

    private

    def read_file
      @file.readlines.map(&:chomp)
    end

    def fill_content(section)
      matches = 0
      loop do
        line = @lines.first
        break unless section.match(line)
        add_to_section(section, line)
        matches += 1
        @lines.shift
      end
      matches
    end

    def add_to_section(section, line)
      if section.singular
        @parsed[section.name] = section.parse(line)
      else
        @parsed[section.name] ||= []
        @parsed[section.name] << section.parse(line)
      end
    end
  end
end