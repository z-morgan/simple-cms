ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils" # methods from this library used in setup and teardown methods

require_relative "../cms"

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  # creates a file, and can populate it with content
  def create_document(name, content = "")
    path = File.join(data_path, name)
    File.open(path, "w") { |file| file.write(content) }
  end

  # provides access to the session data in each request
  def session
    # 'last_request.env' are methods provided by Rack::Test for accessing Rack's internal ENV hash
    # 'rack.session' is the key whose value is a hash containing the session data for a request.
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def setup
    # mkdir_p creates the directories and files in the argument string if they do not exist
    FileUtils.mkdir_p(data_path) # data_path method is defined on main in cms.rb, and is in-scope here

    create_document "history.txt", "2014 - Ruby 2.2 released."
    create_document "changes.txt", "v. 0.9 - started working on the app"
    create_document "about.txt", "This is the about page for my app! "
    create_document "readme.md", "Here is `x = markdown!` Isn't that *swell*?"
  end

  def teardown
    # this method recursively removes the file or directory whose path is passed in.
    FileUtils.rm_rf(data_path)
  end

  def test_index
    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.txt"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, "history.txt"
  end

  def test_viewing_text_document
    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "2014 - Ruby 2.2 released."
  end

  def test_request_nonexistant_document
    get "/not-a-doc.txt"
    assert_equal 302, last_response.status
    assert_equal "not-a-doc.txt does not exist.", session[:msg]
    # assert_equal "http://localhost:4567/", last_response["Location"] # could not figure out why this assertion fails.
    
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "not-a-doc.txt"
    assert_nil session[:msg]
  end

  def test_viewing_markdown_document
    get "/readme.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<em>swell</em>"
  end

  def test_editting_txt_document
    get "/history.txt/edit", {}, admin_session
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "Edit content of history.txt:"
    assert_includes last_response.body, "2014 - Ruby 2.2 released."

    new_text = "1993 - Matz the man dreams up Ruby."
    post "/history.txt/edit", { updated_text: new_text }
    assert_equal 302, last_response.status
    assert_equal "history.txt has been updated.", session[:msg]

    get last_response["Location"]
    assert_nil session[:msg]

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "1993 - Matz the man dreams up Ruby."
  end

  def test_create_unique_document
    get '/', {}, admin_session
    refute_includes last_response.body, "new.txt"
    assert_includes last_response.body, "<a"
    assert_includes last_response.body, "Add a Document"

    get '/new' # is there a way to revieve that href from the 'add a document' anchor? 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form"
    assert_includes last_response.body, %q(type="text")

    post '/new', new_name: "new.txt"
    assert_equal 302, last_response.status
    assert_equal "new.txt has been created.", session[:msg]

    get '/'
    assert_includes last_response.body, "new.txt"
  end

  def test_create_empty_name_retry
    post '/new', { new_name: "" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
    assert_includes last_response.body, "<form"
  end

  def test_duplicate_doc_retry
    post '/new', { new_name: "new.txt" }, admin_session
    post '/new', new_name: "new.txt"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A document with that name already exists."
    assert_includes last_response.body, "<form"
  end

  def test_no_file_extension
    post '/new', { new_name: "new" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "must include a file extention"
    assert_includes last_response.body, "<form"
  end

  def test_delete_document
    get '/', {}, admin_session
    assert_includes last_response.body, %q(<form class="delete")

    post '/delete/history.txt'
    assert_equal 302, last_response.status
    assert_equal "history.txt was deleted.", session[:msg]

    # this is special syntax which removes the :msg from the rack session hash in the rack env hash
    get '/', {}, { "rack.session" => { msg: nil } }
    refute_includes last_response.body, "history.txt"
  end

  def test_signin
    get '/'
    assert_includes last_response.body, "Sign In"
    
    get '/users/signin'
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(input type="password")

    post '/users/signin', username: "admin", password: "secret"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_equal "admin", session[:username]
    assert_includes last_response.body, "Signed in as admin"
    assert_includes last_response.body, "Sign Out"
  end


  def test_signout
    # the next line sets the username to a signed-in state what posting to the signout route
    post '/users/signout', {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "You have signed out.", session[:msg]

    get last_response["Location"]
    assert_includes last_response.body, "Sign In"
  end

  def test_invalid_signin_attempt
    # I'm not sure how ruby interprets the next line as a method with two arguments, and not three. 
    # is this a rack::test specific syntax? Shouldn't the hash elements be wrapped in { } to be passed as a single argument? 
    post '/users/signin', username: "admin", password: "wrong"
    assert_includes last_response.body, "Invalid Credentials."
    assert_equal 422, last_response.status
    assert_includes last_response.body, %q(input type="password")
  end

  def test_restrict_actions_for_signed_out_user
    get '/new'
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:msg]

    get '/file/edit'
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:msg]
    
    post '/file/edit'
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:msg]

    post '/new'
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:msg]

    post '/delete/history.txt'
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:msg]
  end
end

# request methods such as post and get can take two additional arguments
# the first, is a hash which sets parameters to be sent in the request
# the second provides values to be added to the request's Rack.env hash.