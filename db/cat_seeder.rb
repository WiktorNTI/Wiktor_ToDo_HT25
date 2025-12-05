require 'sqlite3'

def seed_categories!(db, db_path = nil)
  puts "Seeding categories in: #{db_path}" if db_path
  drop_cat_table(db)
  create_cat_table(db)
  populate_cat_table(db)
end

def drop_cat_table(db)
  db.execute('DROP TABLE IF EXISTS cat')
end

def create_cat_table(db)
  db.execute('CREATE TABLE cat (
              category_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL)')
end

def populate_cat_table(db)
  %w[Private Public Purchase Do].each do |name|
    db.execute('INSERT INTO cat (name) VALUES (?)', [name])
  end
end

if $PROGRAM_NAME == __FILE__
  db_path = File.expand_path('cat.db', __dir__)
  db = SQLite3::Database.new(db_path)
  seed_categories!(db, db_path)
  puts 'Done seeding categories!'
end
