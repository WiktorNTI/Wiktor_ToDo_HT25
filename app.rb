require 'sinatra'
require 'sqlite3'
require 'slim'
require 'sinatra/reloader'


enable :sessions

# Open a shared connection to the SQLite database
DB = SQLite3::Database.new('db/todos.db')
DB.results_as_hash = true
DB.busy_timeout = 2000
DB.execute('PRAGMA foreign_keys = ON')

def clean_tag_names(raw)
  raw.to_s.split(',').map { |name| name.strip }.reject(&:empty?)
end

def find_or_create_tags(tag_names)
  tag_names.map do |name|
    existing = DB.get_first_value('SELECT category_id FROM cat WHERE LOWER(name) = LOWER(?)', [name])
    next existing.to_i if existing

    DB.execute('INSERT INTO cat (name) VALUES (?)', [name])
    DB.last_insert_row_id
  end
end

def save_tags(todo_id, tag_ids)
  DB.execute('DELETE FROM todo_tags WHERE todo_id = ?', [todo_id])
  tag_ids.uniq.each do |tag_id|
    DB.execute('INSERT INTO todo_tags (todo_id, category_id) VALUES (?, ?)', [todo_id, tag_id])
  end
end

get '/' do
  filter = (params[:filter] || session[:filter] || 'all').to_s
  sort = (params[:sort] || session[:sort] || 'newest').to_s
  selected_tag_ids = Array(params[:tag_ids] || session[:tag_ids] || []).reject(&:empty?).map(&:to_i)

  conditions = []
  binds = []

  if filter == 'complete'
    conditions << 'todos.completed = 1'
  elsif filter == 'incomplete'
    conditions << 'todos.completed = 0'
  else
    filter = 'all'
  end

  if selected_tag_ids.any?
    placeholders = (['?'] * selected_tag_ids.size).join(',')
    conditions << "todos.id IN (SELECT todo_id FROM todo_tags WHERE category_id IN (#{placeholders}))"
    binds.concat(selected_tag_ids)
  end

  order_clause = case sort
                 when 'oldest' then 'todos.id ASC'
                 when 'name_asc' then 'LOWER(todos.name) ASC'
                 when 'name_desc' then 'LOWER(todos.name) DESC'
                 when 'status' then 'todos.completed DESC, todos.id DESC'
                 else
                   sort = 'newest'
                   'todos.id DESC'
                 end

  sql = "SELECT todos.*, GROUP_CONCAT(cat.name, ', ') AS tag_names
         FROM todos
         LEFT JOIN todo_tags tt ON tt.todo_id = todos.id
         LEFT JOIN cat ON cat.category_id = tt.category_id"
  sql += " WHERE #{conditions.join(' AND ')}" if conditions.any?
  sql += ' GROUP BY todos.id'
  sql += " ORDER BY #{order_clause}"

  todos = DB.execute(sql, binds)
  tags = DB.execute('SELECT category_id, name FROM cat ORDER BY name')
  slim(:index, locals: { todos: todos, filter: filter, tags: tags, selected_tag_ids: selected_tag_ids, sort: sort })
end

post '/filter' do
  session[:filter] = params[:filter].to_s
  session[:tag_ids] = Array(params[:tag_ids]).reject(&:empty?)
  session[:sort] = params[:sort].to_s
  redirect '/'
end

#Create new ToDo List
post '/todos' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  selected_tag_ids = Array(params[:tag_ids]).map(&:to_i)
  new_tag_names = clean_tag_names(params[:new_tags])
  selected_tag_ids.concat(find_or_create_tags(new_tag_names))

  DB.transaction
  DB.execute('INSERT INTO todos (name, description, completed) VALUES (?, ?, 0)', [name, description])
  todo_id = DB.last_insert_row_id
  save_tags(todo_id, selected_tag_ids)
  DB.commit
  redirect '/'
end
# Edit ToDo List item
get '/todos/:id/edit' do
  todo = DB.execute('SELECT * FROM todos WHERE id = ?', params[:id].to_i).first
  tags = DB.execute('SELECT category_id, name FROM cat ORDER BY name')
  todo_tag_ids = DB.execute('SELECT category_id FROM todo_tags WHERE todo_id = ?', [todo['id']]).map { |row| row['category_id'].to_i }
  slim(:edit, locals: { todo: todo, tags: tags, todo_tag_ids: todo_tag_ids })
end
 #Update ToDo list item
post '/todos/:id/update' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  selected_tag_ids = Array(params[:tag_ids]).map(&:to_i)
  new_tag_names = clean_tag_names(params[:new_tags])
  selected_tag_ids.concat(find_or_create_tags(new_tag_names))
  DB.execute('UPDATE todos SET name = ?, description = ? WHERE id = ?', [name, description, params[:id].to_i])
  save_tags(params[:id].to_i, selected_tag_ids)
  redirect '/'
end

post '/todos/:id/toggle' do
  completed = params[:completed].to_s == '1' ? 1 : 0
  DB.execute('UPDATE todos SET completed = ? WHERE id = ?', [completed, params[:id].to_i])
  redirect back
end
 #Delete ToDo list item
post '/todos/:id/delete' do
  todo_id = params[:id].to_i
  DB.transaction
  DB.execute('DELETE FROM todo_tags WHERE todo_id = ?', [todo_id])
  DB.execute('DELETE FROM todos WHERE id = ?', todo_id)
  DB.commit
  redirect '/'
end
