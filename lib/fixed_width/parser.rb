class FixedWidth
  class Parser
    def initialize(definition, file)
      @definition = definition
      @file       = file
    end

    # Also by_section=false means try to match each line in the file with a section
    def parse(by_section=true)
      @parsed = {}
      @lines = read_file

      return @parsed if @lines.empty?

      if by_section
        @definition.sections.each do |section|
          rows = fill_content(section)
          raise FixedWidth::RequiredSectionNotFoundError.new("Required section '#{section.name}' was not found.") unless rows > 0 || section.optional
        end
      else
        failed = @lines.map.with_index do |line, index|
          if section = @definition.sections.detect{|s| s.match(line)}
            add_to_section(section, line)
            [section, index]
          else
            [nil, index]
          end
        end.reject{|section, index| section}.map do |_, index|
          "couldn't parse line #{index + 1}"
        end
        if failed.any?
          raise "Unparsable file: #{failed.join(', ')}"
        end
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