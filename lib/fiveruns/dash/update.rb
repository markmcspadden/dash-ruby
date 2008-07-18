require 'zlib'

require 'dash/store/http'
require 'dash/store/file'

module Fiveruns
  
  module Dash
    
    class Update
      
      include Store::HTTP
      include Store::File
      
      def initialize(data, configuration)
        @payload = Payload.new(data)
        @configuration = configuration
      end
      
      def store(*urls)
        uris_by_scheme(urls).each do |scheme, uris|
          __send__("store_#{storage_method_for(scheme)}", uris)
        end
      end
      
      def guid
        @guid ||= timestamp << "_#{Process.pid}"
      end
      
      #######
      private
      #######
      
      def timestamp
        Time.now.strftime('%Y%m%d%H%M%S')
      end
      
      def uris_by_scheme(urls)
        urls.map { |url| URI.parse(url) }.group_by(&:scheme)
      end
      
      def storage_method_for(scheme)
        scheme =~ /^http/ ? :http : :file
      end
      
    end

    class Payload

      attr_reader :info
      def initialize(data)
        @data = data
      end      

      def io
        returning StringIO.new do |io|
          io.write compressed
          io.rewind
        end
      end

      def to_yaml_type
        '!dash.fiveruns.com,2008-07/payload'
      end

      #######
      private
      #######

      def compressed
        Zlib::Deflate.deflate(to_yaml)
      end

    end
        
  end
  
end