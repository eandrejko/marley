module Marley

  # = Top Posts
  # .db file is created in Marley::Configuration::DATA_DIRECTORY (set in <tt>config.yml</tt>)
  class TopPost < ActiveRecord::Base

    ActiveRecord::Base.establish_connection( :adapter => 'sqlite3', :database => File.join(Configuration::DATA_DIRECTORY, 'comments.db') )

    named_scope :top, :order => 'count DESC', :limit => 10
    named_scope :short_top, :order => 'count DESC', :limit => 3
  end
  
end
