module Marley

  require 'digest/md5' # for gravatars
  
  # = Comments for articles
  # .db file is created in Marley::Configuration::DATA_DIRECTORY (set in <tt>config.yml</tt>)
  class Comment < ActiveRecord::Base

    ActiveRecord::Base.establish_connection( :adapter => 'sqlite3', :database => File.join(Configuration::DATA_DIRECTORY, 'comments.db') )

    belongs_to :post

    named_scope :recent,   :order => 'created_at DESC', :limit => 50
    named_scope :ham, :conditions => { :spam => false }
    named_scope :with_post_id, lambda {|i| {:conditions => [ 'post_id = ?', i] }}

    validates_presence_of :author, :email, :body, :post_id

    before_create :fix_urls, :check_spam
    
    def gravatar_url(options = {})
      options[:size] ||= 40
      "http://gravatar.com/avatar/" + Digest::MD5.hexdigest(self.email) + "?s=" + options[:size].to_s
    end
    
    def self.cache_key
      self.maximum(:created_at).to_i.to_s
    end
    
    private

    # See http://railscasts.com/episodes/65-stopping-spam-with-akismet
    def akismet_attributes
      {
        :key                  => CONFIG['akismet']['key'],
        :blog                 => CONFIG['akismet']['url'],
        :user_ip              => self.ip,
        :user_agent           => self.user_agent,
        :referrer             => self.referrer,
        :permalink            => self.permalink,
        :comment_type         => 'comment',
        :comment_author       => self.author,
        :comment_author_email => self.email,
        :comment_author_url   => self.url,
        :comment_content      => self.body
      }
    end
    
    def check_spam
      self.checked = true
      self.spam = Akismetor.spam?(akismet_attributes)
      true # return true so it doesn't stop save
    end

    # TODO : Unit test for this
    def fix_urls
      return unless self.url
      self.url.gsub!(/^(.*)/, 'http://\1') unless self.url =~ %r{^http://} or self.url.empty?
    end
    
  end

end
