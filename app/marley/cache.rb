require 'memcache'
require  File.join(File.dirname(__FILE__),'cache')

module Marley
  class Cache
    def self.cache(key, &block)
      unless CONFIG['memcached']
        raise "Configure memcached in config.yml to be a string like 'localhost:11211' "
      end
      @@connection ||= MemCache.new(CONFIG['memcached'], :namespace => 'Marley/')
      result = @@connection.get(key)
      return result if result
      result = yield
      @@connection.set(key, result)
      result
    end
  end
end