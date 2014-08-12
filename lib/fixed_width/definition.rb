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

    def parser(name, opts = {}, &blk)
      if block_given?
        raise ParseError.new %{
          There is already a defined parser named '#{name}'
        }.squish if parsers[name]
        p = Parser.new(opts.merge(parent: self))
        p.setup(&blk)
        parsers[name] = p
      else
        raise ParseError.new %{
          #parser was given an options hash without a block!
        }.squish unless opts.blank?
      end
      parsers[name]
    end

    def add_schema(schema)
      additions = schema.schemas
      dups = duplicates(schema_map.keys + additions.map(&:name))
      raise DuplicateNameError.new %{
        Definition has duplicate schemas named: #{dups.inspect}
      }.squish unless dups.blank?
      additions.each { |s|
        s.set_opt(:parent, self)
        schema_map[s.name] = s
      }
    end

    def inspect
      string = "#<#{self.class.name}:#{self.object_id}"
      string << " schemas=#{schema_map.keys.inspect}"
      string << ">"
    end

    private

    def schema_map
      @schema_map ||= {}
    end

    def parsers
      @parsers ||= {}
    end

    def duplicates(list)
      counts = list.reduce(Hash.new(0)) { |h,el| h[el] += 1; h }
      counts.select{ |el,c| c > 1 }.keys.sort
    end

  end
end
