module Fiveruns::Dash
  
  class Recipe
    
    class ConfigurationError < ::ArgumentError; end
    
    def self.scope_stack
      @scope_stack ||= []
    end
    
    def self.current
      scope_stack.last
    end
    
    def self.in_scope(recipe)
      scope_stack << recipe
      yield
      scope_stack.pop
    end
    
    attr_reader :name, :url, :options
    def initialize(name, options = {}, &block)
      @name = name
      @options = options
      @url = options[:url]
      @block = block
      validate!
    end
    
    def add_to(configuration)
      self.class.in_scope self do
        @block.call(configuration)
      end
    end
    
    def matches?(criteria)
      criteria.all? { |k, v| options[k] == v }
    end
    
    #######
    private
    #######

    def validate!
      unless @url
        raise ConfigurationError, "Recipe requires :url option"
      end
    end
    
  end
  
end