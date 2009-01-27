require 'rubygems'
require 'ftools'           # ... we wanna access the filesystem ...
require 'yaml'             # ... use YAML for configs and stuff ...
require 'sinatra'          # ... Classy web-development dressed in DSL, http://sinatrarb.heroku.com
require 'activerecord'     # ... or Datamapper? What? :)
require 'rdiscount'        # ... convert Markdown into HTML in blazing speed
require File.join(File.dirname(__FILE__), '..', 'vendor', 'akismetor')   # ... disable comment spam
require File.join(File.dirname(__FILE__), '..', 'vendor', 'githubber')   # ... get repo info

# ... or alternatively, run Sinatra on edge ...
# $:.unshift File.dirname(__FILE__) + 'vendor/sinatra/lib'
# require 'sinatra'

MARLEY_ROOT = File.join(File.dirname(__FILE__), '..') unless defined?(MARLEY_ROOT)

CONFIG = YAML.load_file( File.join(MARLEY_ROOT, 'config', 'config.yml') ) unless defined?(CONFIG)

# -----------------------------------------------------------------------------

# FIXME : There must be a clean way to do this :)
req_or_load = (Sinatra.env == :development) ? :load : :require
%w{configuration.rb post.rb comment.rb top_post.rb vector.rb cache.rb}.each do |f|
  send(req_or_load, File.join(File.dirname(__FILE__), 'marley', f) )
end


# add caching to Sinatra
class Sinatra::Event
  include CacheableEvent
end

# -----------------------------------------------------------------------------

configure do
  theme_directory = Marley::Configuration.directory_for_theme(CONFIG['theme'] || Marley::Configuration::DEFAULT_THEME)
  set_options :views => theme_directory if File.directory?(theme_directory)
end

configure :production do
  not_found { not_found }
  error     { error }
end

helpers do
  
  include Rack::Utils
  alias_method :h, :escape_html

  def markup(string)
    RDiscount::new(string).to_html
  end
  
  def human_date(datetime)
    datetime.strftime('%B %d %Y').gsub(/ 0(\d{1})/, ' \1')
  end

  def rfc_date(datetime)
    datetime.strftime("%Y-%m-%dT%H:%M:%SZ") # 2003-12-13T18:30:02Z
  end

  def hostname
    (request.env['HTTP_X_FORWARDED_SERVER'] =~ /[a-z]*/) ? request.env['HTTP_X_FORWARDED_SERVER'] : request.env['HTTP_HOST']
  end

  def revision
    Marley::Configuration::REVISION || nil
  end

  def not_found
    File.read( File.join( File.dirname(__FILE__), 'public', '404.html') )
  end

  def error
    File.read( File.join( File.dirname(__FILE__), 'public', '500.html') )
  end

end

class Object
  def try(*args)
      options = {:default => nil}.merge(args.last.is_a?(Hash) ? args.pop : {})
      target = self # Initial target is self.
      while target && mtd = args.shift
        target = target.send(mtd) if target.respond_to?(mtd)
      end

      return target || options[:default]
  end
end



def download_file(ext, mime, download = false)
  begin
    name = params[:splat].first if /^[A-Z|a-z|0-9|_|-]+$/.match(params[:splat].first)
    directory = Dir[File.join(Marley::Configuration::DATA_DIRECTORY, '*')].select { |dir| File.directory?(dir)  }.select{|dir| File.exists?(File.join(dir, "#{name}.#{ext}"))}
    send_file(File.join(directory, name + "." + ext), :file_name => File.join(directory, name + "." + ext), :type => mime, :disposition => download ? 'attachment' : 'inline')
  rescue
    throw :halt, [404, not_found ]
  end
  
end

# -----------------------------------------------------------------------------


get '/', :cache_key => Marley::Post.cache_key do
  @posts = Marley::Post.published(:except => [])
  @page_title = "#{CONFIG['blog']['title']}"
  erb :index
end

get '/feed' do
  @posts = Marley::Post.published(:except => [])
  last_modified( @posts.first.updated_on )           # Conditinal GET, send 304 if not modified
  builder :index
end

get '/feed/comments' do
  @comments = Marley::Comment.recent.ham
  last_modified( @comments.first.created_at )        # Conditinal GET, send 304 if not modified
  builder :comments
end

get '/:post_id.html' do
  @post = Marley::Post[ params[:post_id] ]
  throw :halt, [404, not_found ] unless @post
  
  # record this in top posts
  begin
    tp = Marley::TopPost.find_or_create_by_post_id(params[:post_id])
    tp.increment!(:count)
  rescue
    # database is locked, ignore it
    # TODO put correct exception here
  end
  
  @page_title = "#{@post.title} - #{CONFIG['blog']['name']}"
  Sinatra::Cache.cache(@post.cache_key + "/" + params.to_s) {erb :post}
end

post '/:post_id/comments' do
  @post = Marley::Post[ params[:post_id] ]
  throw :halt, [404, not_found ] unless @post
  params.merge!( {
      :ip         => request.env['REMOTE_ADDR'].to_s,
      :user_agent => request.env['HTTP_USER_AGENT'].to_s,
      :referrer   => request.env['REFERER'].to_s,
      :permalink  => "#{hostname}#{@post.permalink}"
  } )
  # puts params.inspect
  @comment = Marley::Comment.create( params )
  if @comment.valid?
    redirect "/"+params[:post_id].to_s+'.html?thank_you=#comment_form'
  else
    @page_title = "#{@post.title} - #{CONFIG['blog']['name']}"
    erb :post
  end
end
get '/:post_id/comments' do 
  redirect "/"+params[:post_id].to_s+'.html#comments'
end

get '/:post_id/feed' do
  @post = Marley::Post[ params[:post_id] ]
  throw :halt, [404, not_found ] unless @post
  last_modified( @post.comments.last.created_at ) if @post.comments.last # Conditinal GET, send 304 if not modified
  builder :post
end

get "/posts/*.jpg" do
  download_file("jpg","image/jpeg")
end

get "/posts/*.pdf" do
  download_file("pdf","application/pdf")
end

get "/posts/*.mov" do
  download_file("mov", "video/quicktime")
end

get "/posts/*.m4v" do
  download_file("m4v", "video/quicktime", true)
end

get "/posts/*.rb" do
  download_file("rb", "text/plain", true)
end

get '/about' do
  "<p style=\"font-family:sans-serif\">I'm running on Sinatra version " + Sinatra::VERSION + '</p>'
end

get '/popular/', :cache_key => Marley::Post.cache_key("popular") do
  @posts = Marley::Post.popular
  throw :halt, [404, not_found ] unless @posts
  @page_title = "#{CONFIG['blog']['title']} #{params[:name]}"
  erb :index  
end

# named finders
get '/:name/' do
  @posts = Marley::Post.send(params[:name])
  throw :halt, [404, not_found ] unless @posts
  @page_title = "#{CONFIG['blog']['title']} #{params[:name]}"
  Sinatra::Cache.cache(Marley::Post.cache_key(params[:name])) {erb :index}
end


# -----------------------------------------------------------------------------