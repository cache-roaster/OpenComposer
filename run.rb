require "sinatra"
require "yaml"
require "erb"
require "pstore"
require "./lib/index"
require "./lib/form"
require "./lib/history"
require "./lib/scheduler"

set :environment, :production
#set :environment, :development
set :erb, trim: "-"

# Internal Constants
VERSION                = "1.3.0"
SCHEDULERS_DIR_PATH    = "./lib/schedulers"
HISTORY_ROWS           = 10
JOB_STATUS             = { "queued" => "QUEUED", "running" => "RUNNING", "completed" => "COMPLETED" }
JOB_ID                 = "id"
JOB_APP_NAME           = "appName"
JOB_APP_PATH           = "appPath"
JOB_STATUS_ID          = "status"
HEADER_SCRIPT_LOCATION = "_script_location"
HEADER_SCRIPT_NAME     = "_script_1"
HEADER_JOB_NAME        = "_script_2"
SCRIPT_CONTENT         = "_script_content"
FORM_LAYOUT            = "_form_layout"
SUBMIT_BUTTON          = "_submitButton"
JOB_NAME               = "Job Name"
JOB_SUBMISSION_TIME    = "Submission Time"
JOB_PARTITION          = "Partition"
JOB_KEYS               = "job_keys"

# Structure of manifest
Manifest = Struct.new(:dirname, :name, :category, :description, :icon, :related_app)

# Create a YAML or ERB file object. Give priority to ERB.
# If the file does not exist or is not valid, return nil.
def read_yaml(yml_path)
  erb_path = yml_path + ".erb"
  if File.exist?(erb_path)
    return YAML.load(ERB.new(File.read(erb_path), trim_mode: "-").result(binding))
  elsif File.exist?(yml_path)
    return YAML.load_file(yml_path)
  else
    return nil
  end
end

# Create a configuration object.
# Defaults are applied for any missing values.
def create_conf
  conf = read_yaml("./conf.yml")

  # Check required values
  ["scheduler", "apps_dir"].each do |key|
    halt 500, "In conf.yml, \"#{key}:\" must be defined." if conf[key].nil?
  end

  conf["login_node"]        ||= nil
  conf["data_dir"]          ||= ENV["HOME"] + "/composer"
  conf["bin"]               ||= nil
  conf["bin_overrides"]     ||= nil
  conf["ssh_wrapper"]       ||= nil
  conf["footer"]            ||= "&nbsp;"
  conf["thumbnail_width"]   ||= "100"
  conf["navbar_color"]      ||= "#3D3B40"
  conf["dropdown_color"]    ||= conf["navbar_color"]
  conf["footer_color"]      ||= conf["navbar_color"]
  conf["category_color"]    ||= "#5522BB"
  conf["description_color"] ||= conf["category_color"]
  conf["form_color"]        ||= "#BFCFE7"

  # Set special environment variables for Grid Engine
  ENV['SGE_ROOT'] ||= conf["sge_root"]

  conf["history_db"] = File.join(conf["data_dir"], conf["scheduler"] + ".db")
  return conf
end

# Create a manifest object in a specified application.
# If the name is not defined, the directory name is used.
def create_manifest(directory_path)
  manifest = read_yaml(File.join(directory_path, "manifest.yml"))
  dirname  = File.basename(directory_path)
  return Manifest.new(dirname, dirname, nil, nil, nil, nil) if manifest.nil?

  manifest["name"] ||= dirname
  related_app = Array(manifest["related_app"]) # If manifest["related_app"] is nil, it will be an empty array.
  
  return Manifest.new(dirname, manifest["name"], manifest["category"], manifest["description"], manifest["icon"], related_app)
end

# Create an array of manifest objects for all applications.
def create_all_manifests(apps_dir)
  Dir.children(apps_dir).each_with_object([]) do |dir, manifests|
    next if dir.start_with?(".") # Skip hidden files and directories

    directory_path = File.join(apps_dir, dir)
    if ["form.yml", "form.yml.erb"].any? { |file| File.exist?(File.join(directory_path, file)) }
      manifests << create_manifest(directory_path)
    end
  end
end

# Replace with cached value.
def replace_with_cache(form, cache)
  form.each do |key, value|
    value["value"] = case value["widget"]
                     when "number", "text", "email"
                       if value.key?("size")
                         value["size"].times.map { |i| cache["#{key}_#{i+1}"] }
                       else
                         cache[key]
                       end
                     when "select", "radio"
                       cache[key]
                     when "multi_select"
                       length = cache["#{key}_length"].to_i
                       length.times.map { |i| cache["#{key}_#{i+1}"] }
                     when "checkbox"
                       value["options"].size.times.map { |i| cache["#{key}_#{i+1}"] }
                     when "path"
                       cache["#{key}"]
                     end
  end
end

# Create a scheduler object.
def create_scheduler(scheduler_name)
  schedulers = Dir.glob(SCHEDULERS_DIR_PATH + "/*.rb").map { |file| File.basename(file, ".rb") }
  halt 500, "No such scheduler_name (#{scheduler_name}) found." unless schedulers.include?(scheduler_name)

  require SCHEDULERS_DIR_PATH + "/" + scheduler_name + ".rb"
  return Object.const_get(scheduler_name.capitalize).new
end

# Create a website of Top, Application, and History.
def show_website(job_id = nil, scheduler = nil, error_msg = nil, error_params = nil)
  @conf         = create_conf
  @apps_dir     = @conf["apps_dir"]
  @version      = VERSION
  @my_ood_url   = request.base_url
  @script_name  = request.script_name
  @path_info    = request.path_info
  @current_path = File.join(@script_name, @path_info)
  @manifests    = create_all_manifests(@apps_dir).sort_by { |m| [(m.category || "").downcase, m.name.downcase] }
  @manifests_w_category, @manifests_wo_category = @manifests.partition(&:category)

  case @path_info
  when "/"
    @name = "Top"
    erb :index
  when "/history"
    @name             = "History"
    @login_node       = @conf["login_node"]
    @scheduler        = scheduler || create_scheduler(@conf["scheduler"])
    @bin              = @conf["bin"]
    @bin_overrides    = @conf["bin_overrides"]
    @ssh_wrapper      = @conf["ssh_wrapper"]
    @status           = params["status"] || "all"
    @filter           = params["filter"]
    @jobs_size        = get_job_size()
    @rows             = [[(params["rows"] || HISTORY_ROWS).to_i, 1].max, @jobs_size].min
    @page_size        = (@rows == 0) ? 1 : ((@jobs_size - 1) / @rows) + 1
    @current_page     = (params["p"] || 1).to_i
    @start_index      = (@jobs_size == 0) ? 0 : (@current_page - 1) * @rows
    @end_index        = (@jobs_size == 0) ? 0 : [@current_page * @rows, @jobs_size].min - 1
    @jobs, @error_msg = get_job_history(@status, @start_index, @end_index, @filter)

    if !@error_msg.nil?
      erb :error
    else
      @error_msg = error_msg
      erb :history
    end
  else # application form
    @manifest = @manifests.find { |m| "/#{m.dirname}" == @path_info }
    if !@manifest.nil?
      @name   = @manifest["name"]
      @body   = read_yaml(File.join(@apps_dir, @path_info, "form.yml"))
      @header = if @body.key?("header")
                  @body["header"]
                else
                  read_yaml("./lib/header.yml")["header"]
                end

      # Since the widget name is used as a variable in Ruby, it should consist of only
      # alphanumeric characters and underscores, and numbers should not be used at the
      # beginning of the name. Furthermore, underscores are also prohibited at the
      # beginning of the name to avoid conflicts with Open Composer's internal variables.
      if @body&.dig("form")
        invalid_keys = @body["form"].each_key.reject { |key| key.match?(/^[a-zA-Z][a-zA-Z0-9_]*$/) }
        halt 500, "Widget name(s) (#{invalid_keys.join(', ')}) cannot be used.\n" unless invalid_keys.empty?
      end
      
      # Load cache
      @script_content = nil
      if params["jobId"] || job_id
        history_db = @conf["history_db"]
        halt 404, "#{history_db} is not found." unless File.exist?(history_db)
        db = PStore.new(history_db)
        cache = ""
        db.transaction(true) do
          id = if params["jobId"]
                 params["jobId"]
               else
                 job_id.is_a?(Array) ? job_id[0].to_s : job_id.to_s
               end
          cache = db[id]
          halt 404, "Specified Job ID (#{id}) is not found." if cache.nil?
        end        
        replace_with_cache(@header, cache)
        replace_with_cache(@body["form"], cache)
        @script_content = cache[SCRIPT_CONTENT]
      elsif !error_msg.nil?
        replace_with_cache(@header, error_params)
        replace_with_cache(@body["form"], error_params)
        @script_content = error_params[SCRIPT_CONTENT]
      end

      @script_label = @body["script"].is_a?(Hash) ? @body["script"]["label"] : "Script Content"
      if @body["script"].is_a?(Hash) && @body["script"].key?("content")
        @body["script"] = @body["script"]["content"]
      end

      @table_index = 1
      @job_id      = job_id.is_a?(Array) ? job_id.join(", ") : job_id
      @error_msg   = error_msg
      erb :form
    else
      @error_msg = "#{request.url} is not found."
      erb :error
    end
  end
end

# Send an application icon.
get "/:apps_dir/:folder/:icon" do
  icon_path = File.join(create_conf["apps_dir"], params[:folder], params[:icon])
  send_file(icon_path) if File.exist?(icon_path)
end

# Return a list of files and/or directories in JSON format.
get "/_files" do
  path = params[:path] || "."
  path = File.dirname(path) if File.file?(path)

  content_type :json
  if File.exist?(path)
    entries = Dir.children(path).map do |entry|
      full_path = File.join(path, entry)
      { name: entry, path: full_path, type: File.directory?(full_path) ? "directory" : "file" }
    end.sort_by { |entry| entry[:name].downcase }
  else
    # When a non-existent directory is specified using the set-value statement of the dynamic form widget.
    entries = ""
  end
  
  { files: entries }.to_json
end

# Return whether the specified PATH is a file or a directory.
get "/_file_or_directory" do
  path = params[:path] || "."
  content_type :json

  if File.file?(path)
    { type: "file" }.to_json
  else
    { type: "directory" }.to_json
  end
end
    
get "/*" do
  show_website
end

post "/*" do
  conf          = create_conf
  bin           = conf["bin"]
  bin_overrides = conf["bin_overrides"]
  ssh_wrapper   = conf["ssh_wrapper"]
  data_dir      = conf["data_dir"]
  history_db    = conf["history_db"]
  scheduler     = create_scheduler(conf["scheduler"])

  if request.path_info == "/history"
    job_ids   = params["JobIds"].split(",")
    error_msg = nil

    case params["action"]
    when "cancel"
      error_msg = scheduler.cancel(job_ids, bin, bin_overrides, ssh_wrapper)
    when "delete"
      if File.exist?(history_db)
        db = PStore.new(history_db)
        db.transaction do
          job_ids.each do |job_id|
            db.delete(job_id)
          end
        end
      end
    end

    show_website(nil, scheduler, error_msg)
  else
    app_path = File.join(conf["apps_dir"], request.path_info)
    
    script_location = params[HEADER_SCRIPT_LOCATION]
    script_name     = params[HEADER_SCRIPT_NAME]
    job_name        = params[HEADER_JOB_NAME]
    halt 500, "#{HEADER_SCRIPT_LOCATION} is not defined in #{app_path}/form.yml[.erb]." if script_location.nil?
    halt 500, "#{HEADER_SCRIPT_NAME} is not defined in #{app_path}/form.yml[.erb]."     if script_name.nil?
    halt 500, "#{HEADER_JOB_NAME} is not defined in #{app_path}/form.yml[.erb]."        if job_name.nil?
    
    script_path    = File.join(script_location, script_name)
    script_content = params[SCRIPT_CONTENT].gsub("\r\n", "\n")
    job_id         = nil
    error_msg      = nil
    form           = read_yaml(File.join(app_path, "form.yml"))
    submit_options = nil
    
    # Run commands in check block
    check = form["check"]
    unless check.nil?
      params.each do |key, value|
        next if ['splat', SCRIPT_CONTENT].include?(key)
        
        suffix = case key
                 when JOB_APP_NAME           then "OC_APP_NAME"
                 when JOB_APP_PATH           then "OC_APP_PATH"
                 when HEADER_SCRIPT_LOCATION then "OC_SCRIPT_LOCATION"
                 when HEADER_SCRIPT_NAME     then "OC_SCRIPT_NAME"
                 when HEADER_JOB_NAME        then "OC_JOB_NAME"
                 else key
                 end

        instance_variable_set("@#{suffix}", value)
      end

      eval(check)
    end
    
    # Run commands in submit block
    submit = form["submit"]
    unless submit.nil?
      replacements = params.each_with_object({}) do |(key, value), env|
        next if ['splat', SCRIPT_CONTENT].include?(key)
        
        suffix = case key
                 when JOB_APP_NAME           then "OC_APP_NAME"
                 when JOB_APP_PATH           then "OC_APP_PATH"
                 when HEADER_SCRIPT_LOCATION then "OC_SCRIPT_LOCATION"
                 when HEADER_SCRIPT_NAME     then "OC_SCRIPT_NAME"
                 when HEADER_JOB_NAME        then "OC_JOB_NAME"
                 else key
                 end
        
        env[suffix] = value
      end

      replacements.each do |key, value|
        if form.dig("form", key)
          widget = form["form"][key]["widget"]
          
          if ["select", "radio", "checkbox"].include?(widget) # TODO: Add support for "multi_select"
            options = form["form"][key]["options"]
            
            options.each do |option|
              if option.is_a?(Array) && value.to_s == option[0]
                value = option[1] if option.size > 1
              end
            end
          end
        end

        submit.gsub!(/\#\{#{key}\}/, value.to_s)
      end

      submit_with_echo = <<~BASH
        #{submit}
        if [ -n "$OC_SUBMIT_OPTIONS" ]; then
          echo "$OC_SUBMIT_OPTIONS"
        else
          echo "__UNDEFINED__"
        fi
        BASH
      
      submit_options = `bash -c '#{submit_with_echo}' | tail -n 1`.strip
      submit_options = nil if submit_options == "__UNDEFINED__"
    end

    # Save a job script
    FileUtils.mkdir_p(script_location)
    File.open(script_path, "w") { |file| file.write(script_content) }

    # Submit a job script
    Dir.chdir(File.dirname(script_path)) do
      job_id, error_msg = scheduler.submit(script_path, job_name.strip, submit_options, bin, bin_overrides, ssh_wrapper)
      params[JOB_SUBMISSION_TIME] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    end

    # Save a job history
    FileUtils.mkdir_p(data_dir)
    db = PStore.new(history_db)
    db.transaction do
      Array(job_id).each do |id|
        db[id] = params
      end
    end
    
    show_website(job_id, scheduler, error_msg, params)
  end
end
