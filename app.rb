require 'sinatra'
require 'sqlite3'
require 'slim'
require 'sinatra/reloader'


# Open a shared connection to the SQLite database
DB = SQLite3::Database.new('db/todos.db')
DB.results_as_hash = true


get '/' do
  filter = params[:filter].to_s
  todos =
    case filter
    when 'complete'
      DB.execute('SELECT * FROM todos WHERE completed = 1 ORDER BY id DESC')
    when 'incomplete'
      DB.execute('SELECT * FROM todos WHERE completed = 0 ORDER BY id DESC')
    else
      filter = 'all'
      DB.execute('SELECT * FROM todos ORDER BY id DESC')
    end

  slim(:index, locals: { todos: todos, filter: filter })
end

#Create new ToDo List
post '/todos' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  halt 400, 'Namn krävs' if name.empty?

  DB.execute('INSERT INTO todos (name, description, completed) VALUES (?, ?, 0)', [name, description])
  redirect '/'
end
# Edit ToDo List item
get '/todos/:id/edit' do
  todo = DB.execute('SELECT * FROM todos WHERE id = ?', params[:id].to_i).first
  halt 404, 'Todo hittades inte' unless todo

  slim(:edit, locals: { todo: todo })
end
 #Update ToDo list item
post '/todos/:id/update' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  DB.execute('UPDATE todos SET name = ?, description = ? WHERE id = ?', [name, description, params[:id].to_i])
  redirect '/'
end

post '/todos/:id/toggle' do
  completed = params[:completed].to_s == '1' ? 1 : 0
  DB.execute('UPDATE todos SET completed = ? WHERE id = ?', [completed, params[:id].to_i])
  redirect back
end
 #Create ToDo list item
post '/todos/:id/delete' do
  DB.execute('DELETE FROM todos WHERE id = ?', params[:id].to_i)
  redirect '/'
end
