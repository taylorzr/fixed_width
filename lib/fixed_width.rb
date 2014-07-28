#
# =DESCRIPTION:
#
# A simple, clean DSL for describing, writing, and parsing fixed-width text files.
#
# =FEATURES:
#
# * Easy DSL syntax
# * Can parse and format fixed width files
# * Templated sections for reuse
#
# For examples, see examples/*.rb or the README.
#
require 'fixed_width/requirements'
module FixedWidth
  class ParserError < RuntimeError; end
  class DuplicateColumnNameError < StandardError; end
  class DuplicateGroupNameError < StandardError; end
  class DuplicateSectionNameError < StandardError; end
  class RequiredSectionNotFoundError < StandardError; end
  class RequiredSectionEmptyError < StandardError; end
  class FormattedStringExceedsLengthError < StandardError; end
  class UnusedLineError < StandardError; end

  #
  # [name]   a symbol to reference this file definition later
  # [option] a hash of default options for all sub-elements
  # and a block that defines the sections of the file.
  #
  # returns: +Definition+ instance for this file description.
  #
  def self.define(name, options={}) # yields definition
    definition = Definition.new(options)
    yield(definition)
    definitions[name] = definition
  end

  #
  # [data]      nested hash describing the contents of the sections
  # [def_name]  symbol +name+ used in +define+
  #
  # returns: string of the transformed +data+ (into fixed-width records).
  #
  def self.generate(def_name, data)
    definition = definitions[def_name]
    raise ArgumentError.new("Definition name '#{def_name}' was not found.") unless definition
    generator = Generator.new(definition)
    generator.generate(data)
  end

  #
  # [io]        IO object to write the +generate+d data
  # [def_name]  symbol +name+ used in +define+
  # [data]      nested hash describing the contents of the sections
  #
  # writes transformed data to +io+ object as fixed-width records.
  #
  def self.write(io, def_name, data)
    io.write(generate(def_name, data))
  end

  #
  # [io]          IO object from which to read the fixed-width text records
  # [def_name]    symbol +name+ used in +define+
  # [parse_opts]  Options hash to pass to Parser#parse
  #
  # returns: parsed text records in a nested hash.
  #
  def self.parse(io, def_name, parse_opts = {})
    definition = definitions[def_name]
    raise ArgumentError.new("Definition name '#{def_name}' was not found.") unless definition
    parser = Parser.new(definition, io)
    parser.parse(parse_opts)
  end

  #
  # [filename]    Filename from which to read the fixed-width text records
  # [def_name]    symbol +name+ used in +define+
  # [parse_opts]  Options hash to pass to Parser#parse
  #
  # returns: parsed text records in a nested hash.
  #
  def self.parseFile(filename, def_name, parse_opts = {})
    File.open(filename, 'r') do |file|
      parse(file, def_name, parse_opts)
    end
  end

  private

  def self.definitions
    @definitions ||= {}
  end

end
