require 'sinatra'
require 'sqlite3'
require 'slim'
require 'sinatra/reloader'


# Open a shared connection to the SQLite database
DB = SQLite3::Database.new('db/todos.db')
DB.results_as_hash = true

get '/' do
  todos = DB.execute('SELECT * FROM todos ORDER BY id DESC')
  slim(:index, locals: { todos: todos })
end

post '/todos' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  halt 400, 'Namn krävs' if name.empty?

  DB.execute('INSERT INTO todos (name, description) VALUES (?, ?)', [name, description])
  redirect '/'
end

get '/todos/:id/edit' do
  todo = DB.execute('SELECT * FROM todos WHERE id = ?', params[:id].to_i).first
  halt 404, 'Todo hittades inte' unless todo

  slim(:edit, locals: { todo: todo })
end

post '/todos/:id/update' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  DB.execute('UPDATE todos SET name = ?, description = ? WHERE id = ?', [name, description, params[:id].to_i])
  redirect '/'
end

post '/todos/:id/delete' do
  DB.execute('DELETE FROM todos WHERE id = ?', params[:id].to_i)
  redirect '/'
end
