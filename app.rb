require 'sinatra'
require 'sqlite3'
require 'slim'
require 'sinatra/reloader'
require 'bcrypt'
require 'securerandom'

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET', SecureRandom.hex(64))

# Open a shared connection to the SQLite database
DB = SQLite3::Database.new('db/todos.db') # Shared connection for the app
DB.results_as_hash = true
DB.busy_timeout = 5000 # avoid short lock errors

DB.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_digest TEXT NOT NULL
  )
SQL

def add_column_if_missing(table, column, type)
  exists = DB.table_info(table).any? { |c| c['name'] == column }
  return if exists

  DB.execute("ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
end

# Ensure per-user scoping columns exist
def ensure_user_scoping!
  add_column_if_missing('todos', 'user_id', 'INTEGER')
  add_column_if_missing('cat', 'user_id', 'INTEGER')
  add_column_if_missing('todo_tags', 'user_id', 'INTEGER')
end

ensure_user_scoping!

helpers do
  # Return current username from session
  def current_user
    session[:user_name].to_s.strip
  end

  # Return current user id from session
  def current_user_id
    session[:user_id].to_i
  end

  # Redirect to landing if not logged in
  def ensure_logged_in!
    redirect '/' if current_user.to_s.strip.empty? || current_user_id.to_s.empty?
  end

  # Remember recent usernames locally in session
  def remember_user(name)
    clean_name = name.to_s.strip
    return if clean_name.empty?

    recent = Array(session[:recent_users])
    recent.delete(clean_name)
    recent.unshift(clean_name)
    session[:recent_users] = recent.first(5)
  end

  def auth_error
    err = session.delete(:auth_error)
    err.to_s.strip
  end

  # Koppla gamla poster som saknar user_id till nuvarande användare
  # Useful if DB had legacy rows without scoping
  def backfill_legacy_records!
    DB.transaction
    DB.execute('UPDATE todos SET user_id = ? WHERE user_id IS NULL', [current_user_id])
    DB.execute('UPDATE cat SET user_id = ? WHERE user_id IS NULL', [current_user_id])
    DB.execute('UPDATE todo_tags SET user_id = ? WHERE user_id IS NULL', [current_user_id])
    DB.commit
  end

  def seed_example_todos_if_empty
    count = DB.get_first_value('SELECT COUNT(*) FROM todos WHERE user_id = ?', [current_user_id]).to_i
    return unless count.zero?

    examples = [
      { name: 'Lägg till din första todo', description: 'Tryck på "Lägg till en ny todo" och skriv in något du vill komma ihåg.', tags: ['Kom igång'] },
      { name: 'Markera som klar', description: 'Använd knappen "Markera som klar" på en todo för att se hur status ändras.', tags: ['Status'] },
      { name: 'Testa taggar', description: 'Lägg till egna taggar och filtrera listan med tagg-filtret högst upp.', tags: ['Taggar'] },
      { name: 'Redigera en todo', description: 'Öppna redigera för att ändra namn eller beskrivning.', tags: ['Redigera'] }
    ]

    examples.each do |ex|
      tag_ids = find_or_create_tags(ex[:tags])
      DB.execute('INSERT INTO todos (name, description, completed, user_id) VALUES (?, ?, 0, ?)', [ex[:name], ex[:description], current_user_id])
      save_tags(DB.last_insert_row_id, tag_ids)
    end
  end

  # Strip and split comma-separated tag names
  def clean_tag_ids_for_current_user(tag_ids)
    return [] if tag_ids.empty?
    placeholders = (['?'] * tag_ids.length).join(',')
    rows = DB.execute("SELECT category_id FROM cat WHERE category_id IN (#{placeholders}) AND user_id = ?", tag_ids + [current_user_id])
    rows.map { |r| r['category_id'].to_i }
  end
end

before do
  protected_paths = [%r{^/todos}, %r{^/filter}, %r{^/tags}]
  needs_login = protected_paths.any? { |pattern| pattern.match?(request.path_info) }
  redirect '/' if needs_login && (current_user.to_s.strip.empty? || current_user_id.to_s.empty?)
end

def find_account_by_username(username)
  DB.get_first_row('SELECT * FROM accounts WHERE LOWER(username) = LOWER(?)', [username.to_s.strip])
end

def create_account(username, password)
  digest = BCrypt::Password.create(password)
  DB.execute('INSERT INTO accounts (username, password_digest) VALUES (?, ?)', [username, digest])
  DB.last_insert_row_id
rescue SQLite3::ConstraintException
  nil
end

# Helper: split comma-separated new tag names
def clean_tag_names(raw)
  raw.to_s.split(',').map { |name| name.strip }.reject { |name| name.empty? }
end

# Find or create tags for the current user
def find_or_create_tags(tag_names)
  default_color = '#FFE135'
  tag_names.map do |name|
    existing = DB.get_first_value('SELECT category_id FROM cat WHERE LOWER(name) = LOWER(?) AND user_id = ?', [name, current_user_id])
    next existing.to_i if existing

    DB.execute('INSERT INTO cat (name, color, user_id) VALUES (?, ?, ?)', [name, default_color, current_user_id])
    DB.last_insert_row_id
  end
end

def save_tags(todo_id, tag_ids)
  cleaned_ids = clean_tag_ids_for_current_user(tag_ids.uniq)
  DB.execute('DELETE FROM todo_tags WHERE todo_id = ? AND user_id = ?', [todo_id, current_user_id])
  cleaned_ids.each do |tag_id|
    DB.execute('INSERT INTO todo_tags (todo_id, category_id, user_id) VALUES (?, ?, ?)', [todo_id, tag_id, current_user_id])
  end
end

get '/' do
  recent_users = Array(session[:recent_users] || [])
  slim(:welcome, locals: { recent_users: recent_users, auth_error: auth_error })
end

post '/signup' do
  username = params[:username].to_s.strip
  password = params[:password].to_s

  if username.empty? || password.empty?
    session[:auth_error] = 'Ange ett användarnamn och ett lösenord.'
    redirect '/'
  end

  if password.length < 4
    session[:auth_error] = 'Lösenordet måste vara minst 4 tecken.'
    redirect '/'
  end

  if find_account_by_username(username)
    session[:auth_error] = 'Användarnamnet är upptaget.'
    redirect '/'
  end

  account_id = create_account(username, password)
  unless account_id
    session[:auth_error] = 'Kunde inte skapa kontot, försök igen.'
    redirect '/'
  end

  session[:user_id] = account_id
  session[:user_name] = username
  session[:filter] = nil
  session[:tag_ids] = nil
  session[:sort] = nil
  backfill_legacy_records!
  seed_example_todos_if_empty
  remember_user(username)
  redirect '/todos'
end

post '/login' do
  username = params[:username].to_s.strip
  username = params[:existing_user].to_s.strip if username.empty?
  password = params[:password].to_s

  if username.empty? || password.empty?
    session[:auth_error] = 'Ange användarnamn och lösenord.'
    redirect '/'
  end

  account = find_account_by_username(username)
  if account.nil? || !BCrypt::Password.new(account['password_digest']).is_password?(password)
    session[:auth_error] = 'Felaktigt användarnamn eller lösenord.'
    redirect '/'
  end

  session[:user_id] = account['id']
  session[:user_name] = account['username']
  session[:filter] = nil
  session[:tag_ids] = nil
  session[:sort] = nil
  backfill_legacy_records!
  seed_example_todos_if_empty
  remember_user(username)
  redirect '/todos'
end

post '/logout' do
  session.delete(:user_name)
  session.delete(:user_id)
  session[:filter] = nil
  session[:tag_ids] = nil
  session[:sort] = nil
  redirect '/'
end

get '/todos' do
  ensure_logged_in!

  filter = (params[:filter] || session[:filter] || 'all').to_s
  sort = (params[:sort] || session[:sort] || 'newest').to_s
  selected_tag_ids = Array(params[:tag_ids] || session[:tag_ids] || [])
                     .reject { |value| value.to_s.empty? }
                     .map { |value| value.to_i }
  selected_tag_ids = clean_tag_ids_for_current_user(selected_tag_ids)

  todos = DB.execute('SELECT * FROM todos WHERE user_id = ?', [current_user_id]).map { |row| row.dup }

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
      tag_rows = DB.execute('SELECT category_id FROM todo_tags WHERE todo_id = ? AND user_id = ?', [todo['id'], current_user_id])
      todo_tag_ids = tag_rows.map { |row| row['category_id'].to_i }
      (todo_tag_ids & selected_tag_ids).any?
    end
  end

  todos.each do |todo|
    tag_rows = DB.execute('SELECT cat.name, IFNULL(cat.color, "#FFE135") AS color
                           FROM cat
                           INNER JOIN todo_tags ON todo_tags.category_id = cat.category_id
                           WHERE todo_tags.todo_id = ?
                           AND cat.user_id = ?
                           AND todo_tags.user_id = ?', [todo['id'], current_user_id, current_user_id])
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

  tags = DB.execute('SELECT category_id, name, IFNULL(color, "#38bdf8") AS color FROM cat WHERE user_id = ? ORDER BY name', [current_user_id])
  slim(:index, locals: { todos: todos, filter: filter, tags: tags, selected_tag_ids: selected_tag_ids, sort: sort })
end

get '/tags' do
  ensure_logged_in!
  tags = DB.execute('SELECT category_id, name, IFNULL(color, "#38bdf8") AS color FROM cat WHERE user_id = ? ORDER BY name', [current_user_id])
  slim(:tags, locals: { tags: tags })
end

post '/tags' do
  ensure_logged_in!
  name = params[:name].to_s.strip
  color = params[:color].to_s.strip
  color = '#FFE135' if color.empty?
  unless name.empty?
    DB.execute('INSERT INTO cat (name, color, user_id) VALUES (?, ?, ?)', [name, color, current_user_id])
  end
  redirect '/tags'
end

post '/filter' do
  ensure_logged_in!
  session[:filter] = params[:filter].to_s
  session[:tag_ids] = Array(params[:tag_ids]).reject { |value| value.to_s.empty? }
  session[:sort] = params[:sort].to_s
  redirect '/todos'
end

#Create new ToDo List
post '/todos' do
  ensure_logged_in!
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  selected_tag_ids = Array(params[:tag_ids]).map { |id| id.to_i }
  selected_tag_ids = clean_tag_ids_for_current_user(selected_tag_ids)
  new_tag_names = clean_tag_names(params[:new_tags])
  selected_tag_ids.concat(find_or_create_tags(new_tag_names))

  DB.transaction
  DB.execute('INSERT INTO todos (name, description, completed, user_id) VALUES (?, ?, 0, ?)', [name, description, current_user_id])
  todo_id = DB.last_insert_row_id
  save_tags(todo_id, selected_tag_ids)
  DB.commit
  redirect '/todos'
end

# Edit ToDo List item
get '/todos/:id/edit' do
  ensure_logged_in!
  todo = DB.execute('SELECT * FROM todos WHERE id = ? AND user_id = ?', [params[:id].to_i, current_user_id]).first
  redirect '/todos' unless todo
  tags = DB.execute('SELECT category_id, name, IFNULL(color, "#38bdf8") AS color FROM cat WHERE user_id = ? ORDER BY name', [current_user_id])
  todo_tag_ids = DB.execute('SELECT category_id FROM todo_tags WHERE todo_id = ? AND user_id = ?', [todo['id'], current_user_id]).map { |row| row['category_id'].to_i }
  slim(:edit, locals: { todo: todo, tags: tags, todo_tag_ids: todo_tag_ids })
end

#Update ToDo list item
post '/todos/:id/update' do
  ensure_logged_in!
  name = params[:name].to_s.strip
  description = params[:description].to_s.strip
  selected_tag_ids = Array(params[:tag_ids]).map { |id| id.to_i }
  selected_tag_ids = clean_tag_ids_for_current_user(selected_tag_ids)
  new_tag_names = clean_tag_names(params[:new_tags])
  selected_tag_ids.concat(find_or_create_tags(new_tag_names))
  DB.execute('UPDATE todos SET name = ?, description = ? WHERE id = ? AND user_id = ?', [name, description, params[:id].to_i, current_user_id])
  save_tags(params[:id].to_i, selected_tag_ids)
  redirect '/todos'
end

post '/todos/:id/toggle' do
  ensure_logged_in!
  completed = params[:completed].to_s == '1' ? 1 : 0
  DB.execute('UPDATE todos SET completed = ? WHERE id = ? AND user_id = ?', [completed, params[:id].to_i, current_user_id])
  redirect '/todos'
end

#Delete ToDo list item
post '/todos/:id/delete' do
  ensure_logged_in!
  todo_id = params[:id].to_i
  DB.transaction
  DB.execute('DELETE FROM todo_tags WHERE todo_id = ? AND user_id = ?', [todo_id, current_user_id])
  DB.execute('DELETE FROM todos WHERE id = ? AND user_id = ?', [todo_id, current_user_id])
  DB.commit
  redirect '/todos'
end

post '/tags/:id/update' do
  ensure_logged_in!
  id = params[:id].to_i
  name = params[:name].to_s.strip
  color = params[:color].to_s.strip
  color = '#FFE135' if color.empty?
  DB.execute('UPDATE cat SET name = ?, color = ? WHERE category_id = ? AND user_id = ?', [name, color, id, current_user_id])
  redirect '/tags'
end

post '/tags/:id/delete' do
  ensure_logged_in!
  id = params[:id].to_i
  DB.transaction
  DB.execute('DELETE FROM todo_tags WHERE category_id = ? AND user_id = ?', [id, current_user_id])
  DB.execute('DELETE FROM cat WHERE category_id = ? AND user_id = ?', [id, current_user_id])
  DB.commit
  redirect '/tags'
end
