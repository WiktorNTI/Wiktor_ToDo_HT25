require 'sinatra'
require 'sqlite3'
require 'slim'
require 'sinatra/reloader'


# Open a shared connection to the SQLite database
DB = SQLite3::Database.new('db/todos.db')
DB.results_as_hash = true

get '/' do
  filter = params[:filter].to_s
  selected_category = params[:category_id].to_s


  filter = session[:filter].to_s if filter.empty? && session[:filter]
  selected_category = session[:category_id].to_s if selected_category.empty? && session[:category_id]

  selected_category_id = selected_category.empty? ? nil : selected_category.to_i

  conditions = []
  binds = []

  case filter
  when 'complete'
    conditions << 'todos.completed = 1'
  when 'incomplete'
    conditions << 'todos.completed = 0'
  else
    filter = 'all'
  end

  if selected_category_id
    conditions << 'todos.category_id = ?'
    binds << selected_category_id
  end

  base_sql = <<~SQL
    SELECT todos.*, cat.name AS category_name
    FROM todos
    LEFT JOIN cat ON cat.category_id = todos.category_id
  SQL
  where_clause = conditions.empty? ? '' : "WHERE #{conditions.join(' AND ')}"
  todos = DB.execute("#{base_sql} #{where_clause} ORDER BY todos.id DESC", binds)

  categories = DB.execute('SELECT category_id, name FROM cat ORDER BY name')
  slim(:index, locals: { todos: todos, filter: filter, categories: categories, selected_category_id: selected_category_id })
end

post '/filter' do
  session[:filter] = params[:filter].to_s
  session[:category_id] = params[:category_id].to_s
  redirect '/'
end

#Create new ToDo List
post '/todos' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  category_param = params[:category_id].to_s
  category_id = category_param.empty? ? nil : category_param.to_i

  DB.execute('INSERT INTO todos (name, description, completed, category_id) VALUES (?, ?, 0, ?)', [name, description, category_id])
  redirect '/'
end
# Edit ToDo List item
get '/todos/:id/edit' do
  todo = DB.execute('SELECT * FROM todos WHERE id = ?', params[:id].to_i).first
  categories = DB.execute('SELECT category_id, name FROM cat ORDER BY name')
  slim(:edit, locals: { todo: todo, categories: categories })
end
 #Update ToDo list item
post '/todos/:id/update' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  category_param = params[:category_id].to_s
  category_id = category_param.empty? ? nil : category_param.to_i
  DB.execute('UPDATE todos SET name = ?, description = ?, category_id = ? WHERE id = ?', [name, description, category_id, params[:id].to_i])
  redirect '/'
end

post '/todos/:id/toggle' do
  completed = params[:completed].to_s == '1' ? 1 : 0
  DB.execute('UPDATE todos SET completed = ? WHERE id = ?', [completed, params[:id].to_i])
  redirect back
end
 #Delete ToDo list item
post '/todos/:id/delete' do
  DB.execute('DELETE FROM todos WHERE id = ?', params[:id].to_i)
  redirect '/'
end
