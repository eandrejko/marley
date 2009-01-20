require 'date'
require 'rdiscount'        # ... convert Markdown into HTML in blazing speed
require  File.join(File.dirname(__FILE__),'vector')
require  File.join(File.dirname(__FILE__),'cache')

module Marley

  # = Articles
  # Data source is Marley::Configuration::DATA_DIRECTORY (set in <tt>config.yml</tt>)
  class Post
    
    # named finders
    @@finders = %w(screencasts)
    
    attr_reader :id, :title, :perex, :body, :body_html, :full_body, :full_body_html, :meta, :published_on, :updated_on, :published, :comments
    
    # comments are referenced via +has_many+ in Comment
    
    def initialize(options={})
      options.each_pair { |key, value| instance_variable_set("@#{key}", value) if self.respond_to? key }
    end
  
    class << self

      def all(options={})
        self.find_all options.merge(:draft => true)
      end
    
      def published(options={})
        self.find_all options.merge(:draft => false)
      end
  
      def [](id, options={})
        self.find_one(id, options)
      end
      alias :find :[] # For +belongs_to+ in Comment

      def popular(options = {})
        options[:limited] ||= 15
        Marley::TopPost.top_limited(options[:limited]).map {|p| self[p.post_id]}
      end

    end
    
    def categories
      self.meta['categories'] if self.meta and self.meta['categories']
    end

    def permalink
      "/#{id}.html"
    end
    
    # related posts
    # turn each of the other posts into a vector and then sort by inner product
    def related(limit = 5, using = 'title')
      v = Marley::Vector.from_string(send(using))
      others = Post.find_all(:except => []).reject{|x| x.id == self.id}
      distances = {}
      others.each do |x|
        key = id < x.id ? "distance-#{id}-#{x.id}" : "distance-#{x.id}-#{id}"
        distances[x.id] = Sinatra::Cache.cache(key){v * Marley::Vector.from_string(x.send(using))}
      end
      others.sort do |a,b|
        distances[b.id] <=> distances[a.id]
      end.select{|x| distances[x.id] > 0}[0..limit-1]
    end
    
    def self.named_finder(name, limit = 5)
      if @@finders.include?(name)
        name = name.gsub("_"," ").gsub(/s$/,'') # easy de-pluralize
        self.find_all(:limit => limit, :except => [], :matching => name)
      else
        nil
      end
    end
    
    # named finders
    def self.method_missing(name, *args)
      name = name.to_s
      self.named_finder(name, *args)
    end
    
    # Caching keys
    def cache_key
      "post/" + Marley::Post.layout_cache_key + "/" + Marley::Comment.ham.cache_key + "/" + updated_on.to_i.to_s
    end
    
    # for collection of posts
    def self.cache_key(name = "")
      "posts/#{name}" + self.find_all.map {|p| p.cache_key}.join("-")
    end
    
    def self.layout_cache_key
      theme_directory = Marley::Configuration.directory_for_theme(CONFIG['theme'] || Marley::Configuration::DEFAULT_THEME)
      Dir[File.join(theme_directory, '*')].map {|f| File.mtime(f)  }.sort.last.to_i.to_s
    end
            
    private
    
    def self.find_all(options={})
      options[:except] ||= ['body', 'body_html']
      options[:limit] ||= 15
      posts = []
      self.extract_posts_from_directory(options).reverse.each do |file|
        break if posts.length == options[:limit]
        matching = options[:matching]
        attributes = self.extract_post_info_from(file, options)
        if matching.nil? || (attributes[:title] =~ /#{matching}/i || attributes[:id] =~ /#{matching}/i)
          attributes.merge!( :comments => Marley::Comment.ham.find_all_by_post_id(attributes[:id], :select => ['id']) )
          posts << self.new( attributes )
        end
      end
      return posts
    end
    
    def self.find_one(id, options={})
      directory = self.load_directories_with_posts(options).select { |dir| dir =~ Regexp.new("#{id}") }
      options.merge!( {:draft => true} )
      # FIXME : Refactor this mess!
      return if directory.empty?
      directory = directory.first
      return unless directory or !File.exist?(directory)
      file = Dir["#{directory}/*.txt"].first
      self.new( self.extract_post_info_from(file, options).merge( :comments => Marley::Comment.ham.find_all_by_post_id(id) ) )
    end
    
    # Returns directories in data directory. Default is published only (no <tt>.draft</tt> in name)
    def self.load_directories_with_posts(options={})
      if options[:draft]
        Dir[File.join(Configuration::DATA_DIRECTORY, '*')].select { |dir| File.directory?(dir)  }.select{|dir| self.after_publish_date(dir)}.sort
      else
        Dir[File.join(Configuration::DATA_DIRECTORY, '*')].select { |dir| File.directory?(dir) and not dir.include?('.draft')  }.select{|dir| self.after_publish_date(dir)}.sort
      end
    end
    
    # determines if post with specified publish date should be published
    def self.after_publish_date(dir)
      if dir =~ /([a-z]{3}-[0-9]{1,2}-[0-9]{4}-[0-9]{2}-[0-9]{2})/
        DateTime.strptime($1 + " " + Configuration::TZ, "%b-%d-%Y-%H-%M %Z") < DateTime.now
      else
        return true
      end
    end
    
    # Loads all directories in data directory and returns first <tt>.txt</tt> file in each one
    def self.extract_posts_from_directory(options={})
      self.load_directories_with_posts(options).collect { |dir| Dir["#{dir}/*.txt"].first }.compact
    end
    
    # Extracts post information from the directory name, file contents, modification time, etc
    # Returns hash which can be passed to <tt>Marley::Post.new()</tt>
    # Extracted attributes can be configured with <tt>:except</tt> and <tt>:only</tt> options
    def self.extract_post_info_from(file, options={})
      raise ArgumentError, "#{file} is not a readable file" unless File.exist?(file) and File.readable?(file)
      options[:except] ||= []
      options[:only]   ||= Marley::Post.instance_methods # FIXME: Refaktorovat!!
      dirname       = File.dirname(file).split('/').last
      file_content  = File.read(file)
      meta_content  = file_content.slice!( self.regexp[:meta] )
      body          = file_content.sub( self.regexp[:title], '').sub( self.regexp[:perex], '').strip
      full_body     = file_content.sub( self.regexp[:title], '').strip
      post          = Hash.new

      post[:id]           = dirname.sub(self.regexp[:id], '\1').sub(/\.draft$/, '').sub(/\.([a-z]{3}-[0-9]{1,2}-[0-9]{4}-[0-9]{2}-[0-9]{2})/, '')
      post[:title], post[:published_on] = file_content.scan( self.regexp[:title_with_date] ).first
      post[:title]        = file_content.scan( self.regexp[:title] ).first.to_s.strip if post[:title].nil?
      post[:published_on] = if dirname =~  /([a-z]{3}-[0-9]{1,2}-[0-9]{4}-[0-9]{2}-[0-9]{2})/
                              DateTime.strptime($1 + " " + Configuration::TZ, "%b-%d-%Y-%H-%M %Z")
                            else
                              File.mtime( File.dirname(file) )                    
                            end
      

      post[:perex]        = RDiscount::new(file_content.scan( self.regexp[:perex] ).first.to_s.strip).to_html unless options[:except].include? 'perex' or
                                                                                      not options[:only].include? 'perex'
      post[:body]         = body                                                      unless options[:except].include? 'body' or
                                                                                      not options[:only].include? 'body'
      post[:body_html]    = RDiscount::new( body ).to_html                            unless options[:except].include? 'body_html' or
                                                                                      not options[:only].include? 'body_html'

      
      post[:full_body_html] = RDiscount::new( full_body ).to_html                            unless options[:except].include? 'body_html' or
                                                                                      not options[:only].include? 'body_html'
      post[:full_body]   =  full_body                            unless options[:except].include? 'body_html' or
                                                                                      not options[:only].include? 'body_html'
      post[:meta]         = ( meta_content ) ? YAML::load( meta_content.scan( self.regexp[:meta]).to_s ) : 
                                               nil unless options[:except].include? 'meta' or not options[:only].include? 'meta'
                                                                                      not options[:only].include? 'published_on'
      post[:updated_on]   = File.mtime( file )                                        unless options[:except].include? 'updated_on' or
                                                                                      not options[:only].include? 'updated_on'
      post[:published]    = !dirname.match(/\.draft$/)                                unless options[:except].include? 'published' or
                                                                                      not options[:only].include? 'published'
      return post
    end
    
    def self.regexp
      { :id    => /^\d{0,4}-{0,1}(.*)$/,
        :title => /^#\s*(.*)\s+$/,
        :title_with_date => /^#\s*(.*)\s+\(([0-9\/]+)\)$/,
        :published_on => /.*\s+\(([0-9\/]+)\)$/,
        :perex => /^\s*\#\s*.*$([^#]+)\s*/, 
        :meta  => /^\{\{\n(.*)\}\}\n$/mi # Multiline Regexp 
      } 
    end
  
  end

end
