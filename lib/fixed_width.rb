require 'fixed_width/requirements'
module FixedWidth

  # Create some shortcuts for prettier code

  def self.define(options={})
    definition = Definition.new(options)
    yield(definition) if block_given?
    definition
  end

  # TODO: remove this once definition.generator exists
  def self.generate(definition, data)
    generator = Generator.new(definition)
    generator.generate(data)
  end

  def self.for_file(filename)
    File.open(filename, 'r') do |file|
      yield file
    end
  end

end
