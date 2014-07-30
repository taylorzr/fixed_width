module FixedWidth
  module Helpers
    def blank
      @blank ||= ->(v){ !v.blank? }
    end
    def to_int
      @to_int ||= ->(v){ Integer(v) }
    end
    def nil_or_proc
      @nil_or_proc ||= ->(v){ v.try(:to_proc) }
    end
  end
end
