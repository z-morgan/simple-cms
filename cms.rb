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
    erb convert_markdown(file_name)
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

get '/new' do
  erb :new
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

def invalid_name(name)
  if name.empty?
    session[:msg] = "A name is required."
  elsif !(name =~ /\.\w+\z/)
    session[:msg] = "The name must include a file extention (such as \".txt\")"
  end
end

post '/new' do
  name = params[:new_name]
  begin
    if invalid_name(name)
      status 422
      erb :new
    else
      path = File.join(data_path, name)

      # the 'x' suffix creates the file, or raises Exeption if it exists already
      File.new(path, 'wx')
      
      session[:msg] = "#{name} has been created."
      redirect '/'
    end
  rescue Errno::EEXIST
    session[:msg] = "A document with that name already exists."
    status 422
    erb :new
  end
end

post '/delete/:field' do # THIS SHOULD BE A POST, AND INDEX.ERB SHOULD USE A FORM
  path = File.join(data_path, params[:field])
  File.delete(path)
  session[:msg] = "#{params[:field]} was deleted."
  redirect '/'
end

# LOOK AT SOLUTION FOR DELETING DOCUMENTS ASSIGNMENT