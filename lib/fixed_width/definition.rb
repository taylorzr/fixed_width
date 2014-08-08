module FixedWidth
  class Definition
    include Config::API

    def initialize(opts={})
      initialize_options(opts)
    end

    def schemata(opts = {}, &blk)
      if block_given?
        schema = Schema.new(opts.merge(name: 'base', parent: self))
        schema.setup(&blk)
        add_schema(schema)
      else
        raise SchemaError.new %{
          #schemata was given an options hash without a block!
        }.squish unless opts.blank?
      end
      schema_map.keys
    end

    def schemas(*keys)
      return schema_map.values if keys.blank?
      keys.map{ |key| schema_map[key] }
    end

    def parser
      #
    end

    def add_schema(schema)
      additions = schema.schemas
      dups = duplicates(schema_map.keys + additions.map(&:name))
      raise DuplicateNameError.new %{
        Definition has duplicate schemas named: #{dups.inspect}
      }.squish unless dups.blank?
      additions.each { |s| schema_map[s.name] = s }
    end

    private

    def schema_map
      @schema_map ||= {}
    end

    def duplicates(list)
      counts = list.reduce(Hash.new(0)) { |h,el| h[el] += 1; h }
      counts.select{ |el,c| c > 1 }.keys.sort
    end

  end
end
