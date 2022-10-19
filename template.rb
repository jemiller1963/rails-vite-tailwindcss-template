# frozen_string_literal: true

require 'fileutils'
require 'shellwords'

def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require 'tmpdir'
    source_paths.unshift(tempdir = Dir.mktmpdir('rails-'))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      '--quiet',
      'https://github.com/IsraelDCastro/rails-vite-tailwindcss-template.git',
      tempdir
    ].map(&:shellescape).join(' ')

    if (branch = __FILE__[%r{rails-vite-tailwindcss-template/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def add_gems
  gem 'vite_rails'
  gem 'vite_ruby'
  gem 'image_processing', '~> 1.2'
  gem 'devise', '~> 4.8'
  gem 'friendly_id', '~> 5.4', '>= 5.4.2'
  gem 'sidekiq', '~> 6.3', '>= 6.3.1'
  gem 'name_of_person', '~> 1.1', '>= 1.1.1'
  gem 'stripe', '>= 2.8', '< 6.0'
  gem "net-http" # Avoiding "already initialized constant errors" with net/protocol
  gem_group :development, :test do
    gem 'annotate'
    gem 'better_errors'  
    gem "hotwire-livereload"
    gem 'rspec-rails'
    gem 'faker'
    gem 'factory_bot_rails'
    gem 'pry'
    gem 'spring-commands-rspec'
    gem 'rubocop', require: false
    gem 'rubocop-performance', require: false
    gem 'rubocop-rails', require: false
    gem 'rubocop-rspec', require: false
  end
end

def set_application_name
  # Add Application Name to Config
  environment 'config.application_name = Rails.application.class.module_parent_name'

  # Announce the user where they can change the application name in the future.
  puts 'You can change application name inside: ./config/application.rb'
end

def add_vite
  run 'bundle exec vite install'
end

def add_javascript
  run 'yarn add autoprefixer postcss sass tailwindcss vite'
  run 'yarn add -D eslint prettier eslint-plugin-prettier eslint-config-prettier eslint-plugin-tailwindcss path vite-plugin-full-reload vite-plugin-ruby'
end

def add_javascript_vue
  run 'yarn add autoprefixer postcss sass tailwindcss vite vue'
  run 'yarn add -D @vitejs/plugin-vue @vue/compiler-sfc eslint prettier eslint-plugin-prettier eslint-config-prettier eslint-plugin-tailwindcss eslint-plugin-vue path vite-plugin-full-reload vite-plugin-ruby'
end

def add_javascript_react
  run 'yarn add autoprefixer postcss sass tailwindcss vite react react-dom'
  run 'yarn add -D @vitejs/plugin-react-refresh eslint prettier eslint-plugin-prettier eslint-config-prettier eslint-plugin-react eslint-plugin-tailwindcss path vite-plugin-full-reload vite-plugin-ruby'
end

def add_testing
  generate "rspec:install"
end

def add_sidekiq
  environment "config.active_job.queue_adapter = :sidekiq"

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<-RUBY
    authenticate :user, lambda { |u| u.admin? } do
      mount Sidekiq::Web => '/sidekiq'
    end
  RUBY
  insert_into_file "config/routes.rb", "#{content}\n\n", after: "Rails.application.routes.draw do\n"
end

def add_friendly_id
  generate "friendly_id"
end

def add_users
  # Install Devise
  generate "devise:install"

  # Configure Devise
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
              env: 'development'

  # route "root to: 'home#index'"

  # Create Devise User
  generate :devise, "User", "first_name", "last_name", "admin:boolean"

  # set admin boolean to false by default
  in_root do
    migration = Dir.glob("db/migrate/*").max_by{ |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  # name_of_person gem
  append_to_file("app/models/user.rb", "\nhas_person_name\n", after: "class User < ApplicationRecord")
end

def copy_templates

  copy_file 'Procfile.dev'
  copy_file 'jsconfig.json'
  copy_file 'tailwind.config.js'
  copy_file 'postcss.config.js'

  # directory 'app', force: true
  directory 'config', force: true
  directory 'lib', force: true

  run 'for file in lib/templates/**/**/*.txt; do mv "$file" "${file%.txt}.tt"; done'
  say '  Custom scaffold templates copied', :green
end

def add_pages_controller
  generate 'controller Pages home'
  route "root to: 'pages#home'"
end

def run_command_flags
  ARGV.each do |flag|
    copy_file 'vite.config-react.ts', 'vite.config.ts' if flag == '--react'
    copy_file '.eslintrc-react.json', '.eslintrc.json' if flag == '--react'
    directory 'app-react', 'app', force: true if flag == '--react'
    add_javascript_react if flag == '--react'

    copy_file 'vite.config-vue.ts', 'vite.config.ts' if flag == '--vue'
    copy_file '.eslintrc-vue.json', '.eslintrc.json' if flag == '--vue'
    directory 'app-vue', 'app', force: true if flag == '--vue'
    add_javascript_vue if flag == '--vue'

    copy_file 'vite.config.ts' if flag == '--normal'
    copy_file '.eslintrc.json' if flag == '--normal'
    directory 'app', force: true if flag == '--normal'
    add_javascript if flag == '--normal'
  end
end

# Main setup
add_gems

after_bundle do
  add_template_repository_to_source_path
  set_application_name
  add_pages_controller
  run_command_flags
  add_users
  add_sidekiq
  add_friendly_id

  copy_templates
  add_vite

  rails_command 'db:create'
  rails_command 'active_storage:install'
  rails_command 'g annotate:install'
  rails_command 'db:migrate'

  begin
    git add: '.'
    git commit: %( -m 'Initial commit' )
  rescue StandardError => e
    puts e.message
  end

  say

  ARGV.each do |flag|
    say 'Rails 7 + Vue 3 + ViteJS + Tailwindcss created!', :green if flag == '--vue'
    say 'Rails 7 + ReactJS 18 + ViteJS + Tailwindcss created!', :green if flag == '--react'
    say 'Rails 7 + ViteJS + Tailwindcss created!', :green if flag == '--normal'
  end

  say
  say '  To get started with your new app:', :yellow
  say "  cd #{original_app_name}"
  say
  say '  # Please update config/database.yml with your database credentials'
  say
  say '  rails s'
end
