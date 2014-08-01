module FixedWidth
  module Config
    class Options

      class << self

        def define(hash)
          option_config = {}
          hash.each do |name, conf|
            begin
              # Add option definition
              key = name.to_sym
              raise FixedWidth::ConfigError.new %{
                Option :'#{key}' is already defined!
              }.squish if option_config.key?(key)
              option_config[key] = {}
              # Setup transformation function
              if transform = replace(conf[:transform])
                transform = transform.to_proc unless transform.is_a?(Proc)
              end
              # Setup validation function
              validate = !conf.key?(:validate) ? nil :
                case (arg = replace(conf[:validate]))
                when Array then err_func( ->(val) { arg.include?(val) },
                  ->(val) { ":#{key} must be one of #{arg.inspect}, got '#{val.inspect}'" } )
                when Proc then err_func( arg,
                  ->(val) { "'#{val.inspect}' is an invalid value for :#{key}" } )
                when Class then err_func( ->(val) { arg === val },
                  ->(val) { ":#{key} must be a #{arg}, got '#{val.inspect}'" } )
                else err_func( ->(val) { arg == val },
                  ->(val) { ":#{key} must equal #{arg}, got '#{val.inspect}'" } )
                end
              # Put it together
              option_config[key][:prepare] = lambda { |value|
                value = transform.call(value) if transform
                validate.call(value) if validate
                value
              }
              # Default Value
              if conf.key?(:default)
                prep = option_config[key][:prepare].call(conf[:default])
                option_config[key][:default] = prep
              end
            rescue => e
              raise if e.is_a?(FixedWidth::BaseError)
              raise FixedWidth::ConfigError.new %{
                Could not add option #{name} due to an error: #{e.inspect}
              }.squish
            end
          end
          new(option_config)
        end

        def functions
          @functions ||= {}
        end

        private

        def err_func(func, err)
          ->(x) { raise FixedWidth::ConfigError.new(err.(x)) unless func.(x) }
        end

        def replace(inp)
          return functions[inp] if functions.key?(inp)
          inp
        end

      end

      def initialize(config)
        @options = config.reduce({}) { |acc, (var,conf)|
          acc[var] = {
            prepare: conf[:prepare],
            required: !!conf[:required]
          }
          acc[var][:default] = conf[:default] if conf.key?(:default)
          acc
        }
        @undefined_options = {}
      end

      def defined?(name)
        keymaker(name) { |key|
          found = options.key?(key)
          found && block_given? ? yield(key) : found
        }
      end

      def set?(name, how = nil)
        self.defined?(name) { |key|
          how = (all = [:value, :default]) & Array(how || all)
          how.any? { |x| options[key].key?(x) }
        }
      end

      def get(name)
        undefined_error!(name) { |key|
          [:value,:default].each { |x|
            return options[key][x] if options[key].key?(x)
          }
          nil
        }
      end

      def set(name, value, undefined = nil)
        key = keymaker(name)
        if self.defined?(key)
          prep = options[key][:prepare].call(value)
          options[key][:value] = prep
        else
          undefined = undefined_options if undefined == true
          if undefined.is_a?(Hash)
            store = ( undefined[key] ||= { undefined: true } )
            store[:value] = value
          else
            undefined_error!(key)
          end
        end
      end

      def require!(name, req = true)
        undefined_error!(name) { |key|
          options[key][:required] = !!req
        }
      end

      def requirements(output = :satisfied?)
        missing = []
        options.each do |key, conf|
          if conf[:required]
            missing << key if !conf.key?(:value) && !conf.key?(:default)
          end
        end
        case output
        when /^satisfied([?]?)$/
          $1 == '?' ? missing.empty? : options.keys - missing
        when /^missing([?]?)$/
          $1 == '?' ? !missing.empty? : missing
        else
          raise FixedWidth::ConfigError.new %{
            The following required fields are missing: #{missing.inspect}
          }.squish unless missing.empty?
          self
        end
      end

      def keys
        options.keys
      end

      def each
        return enum_for(:each) unless block_given?
        options.each do |key, conf|
          yield [key, get(key)]
        end
      end

      def dup
        mopts = { prefer: :other, missing: :import }
        self.class.new({}).merge!(self,mopts)
      end

      def merge(other, mopts)
        dup.merge!(other,mopts)
      end

      def merge!(other, mopts)
        other.each_opt(true) { |conf|
          key = conf[:key]
          if self.defined?(key)
            pref = mopts[:prefer]
            mopt_error(:prefer, pref) unless [:self, :other].include?(pref)
            if using_default?(options[key]) # self is default
              if using_default?(conf) # other is default
                if pref == :other
                  prep = options[key][:prepare].call(value)
                  options[key][:default] = prep
                end
              else # other is value
                set(key, conf[:value])
              end
            else # self is value
              if !using_default?(conf) # other is value
                set(key, conf[:value]) if pref == :other
              end
            end
          else
            mi = mopts[:missing]
            mi_valid = [:import, :raise, :skip, :undefined].include?(mi)
            mopt_error(:missing, mi) unless mi_valid
            case mi
            when :undefined
              undefined_options[key] ||= { undefined: true }
              [:value, :default].each do |vt|
                undefined_options[key][vt] = conf[vt] if conf.key?(vt)
              end
            when :import
              options[key] = conf.reject{ |k,v| k == :key } if conf[:prepare]
            when :raise
              raise FixedWidth::ConfigError.new "Cannot merge option :#{key}"
            end
          end
        }
        self
      end

      protected

      def each_opt(undefined = false)
        return enum_for(:each_opt, undefined) unless block_given?
        over = (undefined && undefined_options) || {}
        over.merge(options).each do |key, conf|
          yield conf.merge(key: key)
        end
      end

      private
      attr_reader :options, :undefined_options

      def using_default?(hash)
        hash.key?(:default) && !hash.key?(:value)
      end

      def keymaker(name)
        begin
          key = name.to_sym
        rescue NoMethodError => nme
          raise unless nme.name == :to_sym
          raise FixedWidth::ConfigError.new %{
            Could not create key for `#{name.inspect}`
          }.squish
        end
        block_given? ? yield(key) : key
      end

      # Error Handling

      def undefined_error!(name)
        if key = self.defined?(name) { |k| k }
          yield(key)
        else
          raise FixedWidth::ConfigError.new %{
            Option '#{name}' is not defined!
          }.squish
        end
      end

      def mopt_error(key, got)
        raise FixedWidth::ConfigError.new %{
          Merge does not understand '#{got}' for :#{key}
        }.squish
      end

    end
  end
end
