require 'sinatra'
set :server, %w(webrick puma thin mongrel)

require 'sinatra/reloader'
require 'tilt/erubis'
require 'sinatra/content_for'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

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

def user_db_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
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

def verify_signed_in
  unless session[:username]
    session[:msg] = "You must be signed in to do that."
    redirect '/'
  end
end

get '/' do
  erb :index
end

get '/new' do
  verify_signed_in

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
  verify_signed_in
  @file_name = params[:file]
  @file_contents = retrieve_contents(@file_name)
  headers["Content-Type"] = "text/html;charset=utf-8"
  erb :edit
end

post '/:file/edit' do
  verify_signed_in
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
  verify_signed_in
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

post '/delete/:field' do
  verify_signed_in
  path = File.join(data_path, params[:field])
  File.delete(path)
  session[:msg] = "#{params[:field]} was deleted."
  redirect '/'
end

get '/users/signin' do
  erb :signin
end

def validate_credentials
  user_db = Psych.load_file(user_db_path)
  user_name = params[:username]
  pass = params[:password]
  user_db.key?(user_name) && BCrypt::Password.new(user_db[user_name]) == pass
end

post '/users/signin' do
  if validate_credentials
    session[:msg] = "Welcome!"
    session[:username] = params[:username]
    redirect '/'
  else
    status 422
    session[:msg] = "Invalid Credentials."
    erb :signin
  end
end

post '/users/signout' do
  session.delete(:username)
  session[:msg] = "You have signed out."
  redirect '/'
end

# Add a form to the index page indicating whether the user is signed in or not
# sign in page is route get '/users/signin, create this route
# create the sign-in view template which posts to /users/signin
# create /users/signin post route which validates creds
# if the creds are incorrect, user is re-presented with sign-in page and a flash
# if the creds are correct, user is redirected to homepage
  # update homepage to include user line which posts to /users/signout
  # create /users/signout post route which signs out and redirects to sign-in page

