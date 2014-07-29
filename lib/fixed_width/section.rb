module FixedWidth
  class Section
    attr_accessor :definition, :optional, :singular
    attr_reader :name, :columns, :options

    def initialize(name, options={})
      @name     = name
      @options  = options
      @columns  = []
      @trap     = options[:trap]
      @optional = options[:optional] || false
      @singular = options[:singular] || false
    end

    def column(name, length, options={})
      # Check for duplicates
      if column_names_by_group(options[:group]).include?(name)
        raise FixedWidth::DuplicateNameError.new %{
          You have already defined a column named '#{name}'
          in the '#{options[:group].inspect}' group.
        }.squish
      end
      if column_names_by_group(nil).include?(options[:group])
        raise FixedWidth::DuplicateNameError.new %{
          You have already defined a column named '#{options[:group]}';
          you cannot have a group and column of the same name.
        }.squish
      end
      if group_names.include?(name)
        raise FixedWidth::DuplicateNameError.new %{
          You have already defined a group named '#{name}';
          you cannot have a group and column of the same name.
        }.squish
      end
      # Add the new column
      col = Column.new(name, length, @options.merge(options))
      @columns << col
      col
    end

    def spacer(length, spacer=nil)
      options           = {}
      options[:padding] = spacer if spacer
      column(:spacer, length, options)
    end

    def trap(&block)
      @trap = block
    end

    def template(name)
      template = @definition.templates(name).first
      raise ArgumentError.new("Template '#{name}' not found as a known template.") unless template
      @columns += template.columns
      # Section options should trump template options
      @options = template.options.merge(@options)
    end

    def format(data)
      @columns.map do |c|
        hash = c.group ? data[c.group] : data
        c.format(hash[c.name])
      end.join
    end

    def parse(line)
      row       = group_names.inject({}) {|h,g| h[g] = {}; h }

      cursor = 0
      @columns.each do |c|
        unless c.name == :spacer
          assignee         = c.group ? row[c.group] : row
          capture = line.mb_chars[cursor..cursor+c.length-1] || ''
          assignee[c.name] = c.parse(capture, self)
        end
        cursor += c.length
      end

      row
    end

    def match(raw_line)
      raw_line.nil? ? false :
        raw_line.length == self.length && @trap.call(raw_line)
    end

    def method_missing(method, *args)
      column(method, *args)
    end

    def length
      @length = nil if @columns_hash != @columns.hash
      @length ||= begin
        @columns_hash = @columns.hash
        @columns.map(&:length).reduce(0,:+)
      end
    end

    private

    def column_names_by_group(group)
      @columns.select{|c| c.group == group }.map(&:name) - [:spacer]
    end

    def group_names
      @columns.map(&:group).compact.uniq
    end

  end
end
