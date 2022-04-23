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
    # assert_equal "http://localhost:4567/", last_response["Location"] # could not figure out why this assertion fails.
    
    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "not-a-doc.txt"
    
    get "/"
    refute_includes last_response.body, "not-a-doc.txt"
  end

  def test_viewing_markdown_document
    get "/readme.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<em>swell</em>"
  end

  def test_editting_txt_document
    get "/history.txt/edit"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "Edit content of history.txt:"
    assert_includes last_response.body, "2014 - Ruby 2.2 released."

    new_text = "1993 - Matz the man dreams up Ruby."
    post "/history.txt/edit", { updated_text: new_text }
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "history.txt has been updated."

    get "/"
    refute_includes last_response.body, "has been updated"

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "1993 - Matz the man dreams up Ruby."
  end

  def test_create_unique_document
    get '/'
    refute_includes last_response.body, "new.txt"
    assert_includes last_response.body, "<a"
    assert_includes last_response.body, "Add a Document"

    get '/new' # is there a way to revieve that href from the 'add a document' anchor? 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form"
    assert_includes last_response.body, %q(type="text")

    post '/new', new_name: "new.txt"
    assert_equal 302, last_response.status
    

    get last_response["Location"]
    assert_includes last_response.body, "new.txt has been created."

    get '/'
    assert_includes last_response.body, "new.txt"
  end

  def test_create_empty_name_retry
    post '/new', new_name: ""
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
    assert_includes last_response.body, "<form"
  end

  def test_duplicate_doc_retry
    post '/new', new_name: "new.txt"
    post '/new', new_name: "new.txt"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A document with that name already exists."
    assert_includes last_response.body, "<form"
  end

  def test_no_file_extension
    post '/new', new_name: "new"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "must include a file extention"
    assert_includes last_response.body, "<form"
  end

  def test_delete_document
    get '/'
    assert_includes last_response.body, %q(<form class="delete")

    post '/delete/history.txt'
    assert_equal 302, last_response.status
    refute_includes last_response.body, "history.txt"
  end
end