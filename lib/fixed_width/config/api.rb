module FixedWidth
  module Config
    module API

      def self.included(base)
        base.extend(ClassMethods)
        FixedWidth::Config::Options.functions.merge!(
          FixedWidth::Config::Helpers::Functions)
      end

      module ClassMethods
        def options
          @opt_wrapper ||= Class.new do
            def initialize(context)
              @context = context
            end
            def opts
              @opts ||= FixedWidth::Config::Options.new({})
            end
            def define(hash)
              defs = FixedWidth::Config::Options.define(hash)
              mopts = { prefer: :raise, missing: :import }
              opts.merge!(defs, mopts)
            end
            def configure(hash)
              hash.each do |key,val|
                iter = (val == :all) ? opts.keys : Array(val).map(&:to_sym)
                case key
                when :required
                  iter.each do |op|
                    opts.require!(op)
                  end
                when :reader
                  iter.each do |op|
                    opts.get(op)
                    @context.send(:define_method, op) { opt(op) }
                  end
                when :writer
                  iter.each do |op|
                    opts.get(op)
                    m = "#{op}=".to_sym
                    @context.send(:define_method, m) { |v| set_opt(op, v) }
                  end
                else
                  raise FixedWidth::ConfigError.new(
                    "Unknown opt_setting '#{key.inspect}'")
                end
              end
            end
          end
          @options ||= @opt_wrapper.new(self)
        end
      end

      def opt(name)
        options.get(name)
      end

      def set_opt(name, value)
        options.set(name, value)
      end

      def options
        @options ||= self.class.options.opts.dup
      end

      private

      def initialize_options(input)
        if input.is_a?(FixedWidth::Config::Options)
          mopts = { prefer: :self, missing: :undefined }
          options.merge!(input, mopts)
        elsif input.is_a?(Hash)
          input.each do |k,v|
            options.set(k,v,true)
          end
        else
          raise FixedWidth::ConfigError.new %{
            Not sure how to initialize options from '#{input.inspect}'
          }.squish
        end
        options.requirements(:raise)
      end

    end
  end
end
