require 'sinatra'
set :server, %w(webrick puma thin mongrel)

require 'sinatra/reloader'
require 'tilt/erubis'
require 'sinatra/content_for'
require 'redcarpet'

configure do
  enable :sessions
  set :session_secret, 'secret'
end

before do
  @files = Dir.children(data_path).sort
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def retrieve_contents(file_name)
  if file_name.include?(".txt")
    retrieve_txt(file_name)
  elsif file_name.include?(".md")
    convert_markdown(file_name)
  end
end

def retrieve_txt(file_name)
  headers["Content-Type"] = "text/plain"
  path = File.join(data_path, file_name)
  File.open(path).read  # need a slash here?
end

def convert_markdown(file_name)
  headers["Content-Type"] = "text/html;charset=utf-8"
  path = File.join(data_path, file_name)
  content = File.open(path).read
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(content)
end

get '/' do
  erb :index
end

get '/:file' do
  file_name = params[:file]
  if @files.include? file_name
    retrieve_contents(file_name)
  else
    session[:msg] = "#{file_name} does not exist." 
    redirect "/"
  end
end

get '/:file/edit' do
  @file_name = params[:file]
  @file_contents = retrieve_contents(@file_name)
  headers["Content-Type"] = "text/html;charset=utf-8"
  erb :edit
end

post '/:file/edit' do
  file_name = params[:file]
  path = File.join(data_path, file_name)
  File.write(path, params[:updated_text])
  session[:msg] = "#{file_name} has been updated."
  redirect '/'
end

