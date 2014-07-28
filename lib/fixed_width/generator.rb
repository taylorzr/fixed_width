module FixedWidth
  class Generator

    def initialize(definition)
      @definition = definition
    end

    def generate(data)
      @builder = []
      @definition.sections.each do |section|
        content = data[section.name]
        arrayed_content = Array.wrap(content)
        if !section.optional && arrayed_content.empty?
          raise FixedWidth::RequiredSectionEmptyError.new(
            "Required section '#{section.name}' was empty. Pass optional: true if this is wrong."
          )
        end
        arrayed_content.each {|row| @builder << section.format(row) }
      end
      @builder.join("\n")
    end

  end
end
