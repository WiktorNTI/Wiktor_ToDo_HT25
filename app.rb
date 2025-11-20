require 'sinatra'
require 'sqlite3'
require 'slim'

# Open a shared connection to the SQLite database
DB = SQLite3::Database.new('db/todos.db')
DB.results_as_hash = true

get '/' do
  todos = DB.execute('SELECT * FROM todos')
  slim(:index, locals: { todos: todos })
end

post '/' do
  DB.execute('INSERT INTO todos (name, description) VALUES (?, ?)', [params[:name], params[:description]])
  redirect '/'
end
