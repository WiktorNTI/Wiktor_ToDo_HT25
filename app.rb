require 'sinatra'
require 'sqlite3'
require 'slim'
require 'sinatra/reloader'


# Open a shared connection to the SQLite database
DB = SQLite3::Database.new('db/todos.db')
DB.results_as_hash = true

def clean_tag_names(raw)
  raw.to_s.split(',').map { |name| name.strip }.reject { |name| name.empty? }
end

def find_or_create_tags(tag_names)
  default_color = '#38bdf8'
  tag_names.map do |name|
    existing = DB.get_first_value('SELECT category_id FROM cat WHERE LOWER(name) = LOWER(?)', [name])
    next existing.to_i if existing

    DB.execute('INSERT INTO cat (name, color) VALUES (?, ?)', [name, default_color])
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
  selected_tag_ids = Array(params[:tag_ids] || session[:tag_ids] || [])
                     .reject { |value| value.to_s.empty? }
                     .map { |value| value.to_i }

  todos = DB.execute('SELECT * FROM todos').map { |row| row.dup }

  todos = todos.select do |todo|
    case filter
    when 'complete' then todo['completed'].to_i == 1
    when 'incomplete' then todo['completed'].to_i == 0
    else
      filter = 'all'
      true
    end
  end

  if selected_tag_ids.any?
    todos = todos.select do |todo|
      tag_rows = DB.execute('SELECT category_id FROM todo_tags WHERE todo_id = ?', [todo['id']])
      todo_tag_ids = tag_rows.map { |row| row['category_id'].to_i }
      (todo_tag_ids & selected_tag_ids).any?
    end
  end

  todos.each do |todo|
    tag_rows = DB.execute('SELECT cat.name, IFNULL(cat.color, "#38bdf8") AS color
                           FROM cat
                           INNER JOIN todo_tags ON todo_tags.category_id = cat.category_id
                           WHERE todo_tags.todo_id = ?', [todo['id']])
    todo['parsed_tags'] = tag_rows
  end

  case sort
  when 'oldest'
    todos.sort_by! { |todo| todo['id'].to_i }
  when 'name_asc'
    todos.sort_by! { |todo| todo['name'].to_s.downcase }
  when 'name_desc'
    todos.sort_by! { |todo| todo['name'].to_s.downcase }
    todos.reverse!
  when 'status'
    todos.sort_by! { |todo| todo['completed'].to_i }
    todos.reverse!
  else
    sort = 'newest'
    todos.sort_by! { |todo| todo['id'].to_i }
    todos.reverse!
  end

  tags = DB.execute('SELECT category_id, name, IFNULL(color, "#38bdf8") AS color FROM cat ORDER BY name')
  slim(:index, locals: { todos: todos, filter: filter, tags: tags, selected_tag_ids: selected_tag_ids, sort: sort })
end

post '/filter' do
  session[:filter] = params[:filter].to_s
  session[:tag_ids] = Array(params[:tag_ids]).reject { |value| value.to_s.empty? }
  session[:sort] = params[:sort].to_s
  redirect '/'
end

#Create new ToDo List
post '/todos' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  selected_tag_ids = Array(params[:tag_ids]).map { |id| id.to_i }
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
  tags = DB.execute('SELECT category_id, name, IFNULL(color, "#38bdf8") AS color FROM cat ORDER BY name')
  todo_tag_ids = DB.execute('SELECT category_id FROM todo_tags WHERE todo_id = ?', [todo['id']]).map { |row| row['category_id'].to_i }
  slim(:edit, locals: { todo: todo, tags: tags, todo_tag_ids: todo_tag_ids })
end
 #Update ToDo list item
post '/todos/:id/update' do
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  selected_tag_ids = Array(params[:tag_ids]).map { |id| id.to_i }
  new_tag_names = clean_tag_names(params[:new_tags])
  selected_tag_ids.concat(find_or_create_tags(new_tag_names))
  DB.execute('UPDATE todos SET name = ?, description = ? WHERE id = ?', [name, description, params[:id].to_i])
  save_tags(params[:id].to_i, selected_tag_ids)
  redirect '/'
end

post '/todos/:id/toggle' do
  completed = params[:completed].to_s == '1' ? 1 : 0
  DB.execute('UPDATE todos SET completed = ? WHERE id = ?', [completed, params[:id].to_i])
  redirect '/'
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

post '/tags/:id/update' do
  id = params[:id].to_i
  name = params[:name].to_s.strip
  color = params[:color].to_s.strip
  color = '#38bdf8' if color.empty?
  DB.execute('UPDATE cat SET name = ?, color = ? WHERE category_id = ?', [name, color, id])
  redirect '/'
end

post '/tags/:id/delete' do
  id = params[:id].to_i
  DB.transaction
  DB.execute('DELETE FROM todo_tags WHERE category_id = ?', [id])
  DB.execute('DELETE FROM cat WHERE category_id = ?', [id])
  DB.commit
  redirect '/'
end
