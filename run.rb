require "sinatra"
require "yaml"
require "erb"
require "pstore"
require "./lib/index"
require "./lib/form"
require "./lib/history"
require "./lib/scheduler"

# set :environment, :production
set :environment, :development
set :erb, trim: "-"

# Internal Constants
VERSION                = "1.5.0"
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
HEADER_CLUSTER_NAME    = "_cluster_name"
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
# If the file does not exist, return nil.
def read_yaml(yml_path)
  erb_path = yml_path + ".erb"
  if File.exist?(erb_path)
    return YAML.load(ERB.new(File.read(erb_path), trim_mode: "-").result(binding))
  elsif File.exist?(yml_path)
    return YAML.load_file(yml_path)
  end
  
  return nil
end

# Create a configuration object.
# Defaults are applied for any missing values.
def create_conf
  begin
    conf = read_yaml("./conf.yml")
    halt 500, "./conf.yml.erb does not be found." if conf.nil?
  rescue Exception => e
    halt 500, "There is something wrong with ./conf.yml or ./conf.yml.erb."
  end

  # Check required values
  halt 500, "In ./conf.yml.erb, \"apps_dir:\" must be defined." unless conf.key?("apps_dir")
  halt 500, "In ./conf.yml.erb, either \"scheduler:\" or \"cluster:\" must be defined, but not both." unless conf.key?("scheduler") ^ conf.key?("cluster")
  if conf.key?("cluster")
    ["bin", "bin_overrides", "sge_root"].each do |key|
      halt 500, "In ./conf.yml.erb, \"#{key}:\" can only be defined in \"cluster:\"." if conf.key?(key)
    end
    halt 500, "In ./conf.yml.erb, \"cluster:\" must be an array." unless conf['cluster'].is_a?(Array)
    conf["cluster"].each do |c|
      ["name", "scheduler"].each do |key|
        halt 500, "In ./conf.yml.erb, \"cluster:\" must have \"#{key}:\"." unless c.key?(key)
      end
    end
  end

  # Set initial values if not defined
  conf["data_dir"]          ||= ENV["HOME"] + "/composer"
  conf["footer"]            ||= "&nbsp;"
  conf["thumbnail_width"]   ||= "100"
  conf["navbar_color"]      ||= "#3D3B40"
  conf["dropdown_color"]    ||= conf["navbar_color"]
  conf["footer_color"]      ||= conf["navbar_color"]
  conf["category_color"]    ||= "#5522BB"
  conf["description_color"] ||= conf["category_color"]
  conf["form_color"]        ||= "#BFCFE7"

  # Set the values for "cluster:" and "history_db"
  if conf.key?("cluster")
    conf["scheduler"]     = {}
    conf["bin"]           = {}
    conf["bin_overrides"] = {}
    conf["sge_root"]      = {}
    conf["history_db"]    = {}
    
    conf['cluster'].each do |c|
      cluster_name = c["name"]
      ["scheduler", "bin", "bin_overrides", "sge_root"].each do |key|
        conf[key][cluster_name] = c[key]
      end
      conf["history_db"][cluster_name] = File.join(conf["data_dir"], cluster_name + ".db")
    end
  else
    conf["history_db"] = File.join(conf["data_dir"], conf["scheduler"] + ".db")
  end
  
  ENV['PBS_API_ENDPOINT'] ||= conf["pbs_api_endpoint"]
  token_path = File.expand_path(conf["pbs_api_token_path"])
  ENV['PBS_API_TOKEN'] ||= File.read(token_path).strip

  return conf
end

# Create a manifest object in a specified application.
# If the name is not defined, the directory name is used.
def create_manifest(app_path)
  begin
    manifest = read_yaml(File.join(app_path, "manifest.yml"))
  rescue Exception => e
    return nil
  end

  dirname = File.basename(app_path)
  return Manifest.new(dirname, dirname, nil, nil, nil, nil) if manifest.nil?

  manifest["name"] ||= dirname
  return Manifest.new(dirname, manifest["name"], manifest["category"], manifest["description"], manifest["icon"], manifest["related_app"])
end

# Create an array of manifest objects for all applications.
def create_all_manifests(apps_dir)
  all_manifests = Dir.children(apps_dir).each_with_object([]) do |dir, manifests|
    next if dir.start_with?(".") # Skip hidden files and directories

    app_path = File.join(apps_dir, dir)
    if ["form.yml", "form.yml.erb"].any? { |file| File.exist?(File.join(app_path, file)) }
      manifests << create_manifest(app_path)
    end
  end

  return all_manifests.compact
end

# Replace with cached value.
def replace_with_cache(form, cache)
  form.each do |key, value|
    value["value"] = case value["widget"]
                     when "number", "text", "email"
                       if value.key?("size")
                         value["size"].times.map do |i|
                           cache["#{key}_#{i+1}"] || Array(value["value"])[i]  # Array(nil)[i] is nil
                         end
                       else
                         cache[key] || value["value"]
                       end
                     when "select", "radio"
                       cache[key] || value["value"]
                     when "multi_select"
                       length = cache["#{key}_length"]&.to_i || 0
                       length.times.map { |i| cache["#{key}_#{i+1}"] }
                     when "checkbox"
                       value["options"].size.times.map { |i| cache["#{key}_#{i+1}"] }.compact
                     when "path"
                       cache["#{key}"] || value["value"]
                     end
  end
end

# Create a scheduler object.
def create_scheduler(conf)
  available = Dir.glob("#{SCHEDULERS_DIR_PATH}/*.rb").map { |f| File.basename(f, ".rb") }

  if conf.key?("cluster")
    schedulers = {}

    conf["scheduler"].each do |cluster_name, scheduler_name|
      halt 500, "No such scheduler_name (#{scheduler_name}) found." unless available.include?(scheduler_name)

      require "#{SCHEDULERS_DIR_PATH}/#{scheduler_name}.rb"
      schedulers[cluster_name] = Object.const_get(scheduler_name.capitalize).new
    end
  else
    scheduler_name = conf["scheduler"]
    halt 500, "No such scheduler_name (#{scheduler_name}) found." unless available.include?(scheduler_name)

    require "#{SCHEDULERS_DIR_PATH}/#{scheduler_name}.rb"
    schedulers = Object.const_get(scheduler_name.capitalize).new
  end

  schedulers
end

# Create a website of Top, Application, and History.
def show_website(job_id = nil, error_msg = nil, error_params = nil)
  @conf          = create_conf
  @apps_dir      = @conf["apps_dir"]
  @login_node    = @conf["login_node"]
  @version       = VERSION
  @my_ood_url    = request.base_url
  @script_name   = request.script_name
  @path_info     = request.path_info
  @cluster_name  = if @conf.key?("cluster")
                     escape_html(params[@path_info == "/history" ? "cluster" : HEADER_CLUSTER_NAME] || @conf["cluster"].first["name"])
                   else
                     nil
                   end
  @ood_logo_path = URI.join(@my_ood_url, @script_name + "/", "ood.png")
  @current_path  = File.join(@script_name, @path_info)
  @manifests     = create_all_manifests(@apps_dir).sort_by { |m| [(m.category || "").downcase, m.name.downcase] }
  @manifests_w_category, @manifests_wo_category = @manifests.partition(&:category)

  case @path_info
  when "/"
    @name = "Top"
    return erb :index
  when "/history"
    @name          = "History"
    @scheduler     = create_scheduler(@conf)
    @bin           = @conf["bin"]
    @bin_overrides = @conf["bin_overrides"]
    @ssh_wrapper   = @conf["ssh_wrapper"]
    @error_msg     = update_status(@conf, @scheduler, @bin, @bin_overrides, @ssh_wrapper, @cluster_name)
    return erb :error if @error_msg != nil

    @status       = escape_html(params["status"] || "all")
    @filter       = escape_html(params["filter"])
    all_jobs      = get_all_jobs(@conf, @cluster_name, @status, @filter)
    @jobs_size    = all_jobs.size
    @rows         = [[(params["rows"] || HISTORY_ROWS).to_i, 1].max, @jobs_size].min
    @page_size    = (@rows == 0) ? 1 : ((@jobs_size - 1) / @rows) + 1
    @current_page = (params["p"] || 1).to_i
    @start_index  = @jobs_size == 0 ? 0 : (@current_page - 1) * @rows
    @end_index    = @jobs_size == 0 ? 0 : [@current_page * @rows, @jobs_size].min - 1
    @jobs         = @start_index >= @jobs_size ? [] : all_jobs[@start_index..@end_index]
    @error_msg    = error_msg
    return erb :history
  else # application form
    @table_index = 1
    @manifest = @manifests.find { |m| "/#{m.dirname}" == @path_info }
    unless @manifest.nil?
      begin
        @body = read_yaml(File.join(@apps_dir, @path_info, "form.yml"))
        @header = if @body.key?("header")
                    @body["header"]
                  else
                    read_yaml("./lib/header.yml")["header"]
                  end
      rescue Exception => e
        @error_msg = e.message
        return erb :error
      end
      @name = @manifest["name"]
      
      # Since the widget name is used as a variable in Ruby, it should consist of only
      # alphanumeric characters and underscores, and numbers should not be used at the
      # beginning of the name. Furthermore, underscores are also prohibited at the
      # beginning of the name to avoid conflicts with Open Composer's internal variables.
      if @body&.dig("form")
        invalid_keys = @body["form"].each_key.reject { |key| key.match?(/^[a-zA-Z][a-zA-Z0-9_]*$/) }
        unless invalid_keys.empty?
          @error_msg = "Widget name(s) (#{invalid_keys.join(', ')}) cannot be used.\n"
          return erb :error
        end
      end

      # Load cache
      @script_content = nil
      if params["jobId"] || job_id
        history_db = if @conf.key?("cluster")
                       cluster_name = params[params["jobId"] ? "cluster" : HEADER_CLUSTER_NAME] || @conf["cluster"].first["name"]
                       @conf["history_db"][cluster_name]
                     else
                       @conf["history_db"]
                     end

        if history_db.nil? || !File.exist?(history_db)
          @error_msg = history_db.nil? ? "#{cluster_name} is not invalid." : "#{history_db} is not found."
          return erb :error
        end

        cache = nil
        id = nil
        db = PStore.new(history_db)
        db.transaction(true) do
          id = if params["jobId"]
                 params["jobId"]
               else
                 job_id.is_a?(Array) ? job_id[0].to_s : job_id.to_s
               end
          cache = db[id]
        end

        if cache.nil?
          @error_msg = "Specified Job ID (#{id}) is not found."
          return erb :error
        end

        replace_with_cache(@header, cache)
        replace_with_cache(@body["form"], cache)
        @script_content = escape_html(cache[SCRIPT_CONTENT])
      elsif !error_msg.nil? # When job submission failed
        replace_with_cache(@header, error_params)
        replace_with_cache(@body["form"], error_params)
        @script_content = escape_html(error_params[SCRIPT_CONTENT])
      end

      # Set script content
      @script_label = @body["script"].is_a?(Hash) ? @body["script"]["label"] : "Script Content"
      if @body["script"].is_a?(Hash) && @body["script"].key?("content")
        @body["script"] = @body["script"]["content"]
      end

      @job_id    = job_id.is_a?(Array) ? job_id.join(", ") : job_id
      @error_msg = error_msg&.force_encoding('UTF-8')
      return erb :form
    else
      @error_msg = "#{request.url} is not found."
      return erb :error
    end
  end
end

# Raise a RuntimeError with the given message if the condition is false.
# This function is used in a check section of form.yml[.erb].
def oc_assert(condition, message = "Error exists in script content.")
  raise RuntimeError, message unless condition
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
  cluster_name  = if conf.key?("cluster")
                    params[request.path_info == "/history" ? "cluster" : HEADER_CLUSTER_NAME] || conf["cluster"].first["name"]
                  else
                    nil
                  end
  bin           = conf.key?("cluster") ? conf["bin"][cluster_name] : conf["bin"]
  bin_overrides = conf.key?("cluster") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  history_db    = conf.key?("cluster") ? conf["history_db"][cluster_name] : conf["history_db"]
  scheduler     = conf.key?("cluster") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  ssh_wrapper   = conf["ssh_wrapper"]
  data_dir      = conf["data_dir"]
  ENV['SGE_ROOT'] ||= conf.key?("cluster") ? conf["sge_root"][cluster_name] : conf["sge_root"]

  if request.path_info == "/history"
    job_ids   = params["JobIds"].split(",")
    error_msg = nil

    case params["action"]
    when "DeleteJob"
      error_msg = scheduler.delete(job_ids, bin, bin_overrides, ssh_wrapper)
    when "DeleteInfo"
      if File.exist?(history_db)
        db = PStore.new(history_db)
        db.transaction do
          job_ids.each do |job_id|
            db.delete(job_id)
          end
        end
      end
    end

    return show_website(nil, error_msg)
  else # application form
    app_path = File.join(conf["apps_dir"], request.path_info)
    
    script_location = params[HEADER_SCRIPT_LOCATION]
    script_name     = params[HEADER_SCRIPT_NAME]
    job_name        = params[HEADER_JOB_NAME]
    error_msg =
      if script_location.nil?
        "#{HEADER_SCRIPT_LOCATION} is not defined in #{app_path}/form.yml[.erb]."
      elsif script_name.nil?
        "#{HEADER_SCRIPT_NAME} is not defined in #{app_path}/form.yml[.erb]."
      elsif job_name.nil?
        "#{HEADER_JOB_NAME} is not defined in #{app_path}/form.yml[.erb]."
      else
        nil
      end
    return show_website(nil, error_msg, params) if error_msg
    
    begin
      form = read_yaml(File.join(app_path, "form.yml"))
    rescue Exception => e
      @error_msg = e.message
      return erb :error
    end

    script_path    = File.join(script_location, script_name)
    script_content = params[SCRIPT_CONTENT].gsub("\r\n", "\n")
    job_id         = nil
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
                 when HEADER_CLUSTER_NAME    then "OC_CLUSTER_NAME"
                 else key
                 end

        instance_variable_set("@#{suffix}", value)
      end
      
      begin
        eval(check)
      rescue Exception => e
        return show_website(nil, e.message, params)
      end
    end

    # Save a job script
    FileUtils.mkdir_p(script_location)
    File.open(script_path, "w") { |file| file.write(script_content) }
    
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
                 when HEADER_CLUSTER_NAME    then "OC_CLUSTER_NAME"
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
        set -e # Enable error exit
        #{submit}
        if [ -n "$OC_SUBMIT_OPTIONS" ]; then
          echo "$OC_SUBMIT_OPTIONS"
        else
          echo "__UNDEFINED__"
        fi
        BASH

      stdout, stderr, status = Open3.capture3("bash", "-c", submit_with_echo)
      unless status.success?
        return show_website(nil, stderr, params)
      end
      
      last_line = stdout.lines.last&.strip
      submit_options = (last_line == "__UNDEFINED__") ? nil : last_line
    end

    # Submit a job script
    Dir.chdir(File.dirname(script_path)) do
      job_id, error_msg = scheduler.submit(script_path, escape_html(job_name.strip), submit_options, bin, bin_overrides, ssh_wrapper)
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

    return show_website(job_id, error_msg, params)
  end
end
