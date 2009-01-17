require 'memcache'
require  File.join(File.dirname(__FILE__),'cache')
require 'digest/md5' # for gravatars

module Marley
  class Cache
    def self.cache(key, &block)
      unless CONFIG['memcached']
        raise "Configure memcached in config.yml to be a string like 'localhost:11211' "
      end
      begin
        key = Digest::MD5.hexdigest(key)
        @@connection ||= MemCache.new(CONFIG['memcached'], :namespace => 'Marley/')
        result = @@connection.get(key)
        return result if result
        result = yield
        @@connection.set(key, result)
        result
      rescue
        yield
      end
    end
  end
end