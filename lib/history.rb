helpers do
  # Generate HTML for icons linking to related applications.
  def output_related_app_icon(job_apps_path, apps)
    return [] if apps.nil?
    
    apps.map do |app|
      if app.is_a?(Hash)
        # Extract key and value from the hash
        key, value = app.first
        href = "#{@my_ood_url}/pun/sys/dashboard/batch_connect/sys/#{key}"
        is_bi_or_fa_icon, icon_path = get_icon_path(job_apps_path, value)
        
        # Generate icon HTML based on whether it's a Bootstrap/Font Awesome icon or an image
        icon_html = if is_bi_or_fa_icon
                      "<i class=\"#{value} fs-5\"></i>"
                    else
                      "<img width=20 title=\"#{key}\" alt=\"#{key}\" src=\"#{icon_path}\">"
                    end
      else
        # Handle cases where app is not a hash (direct app name)
        key = app
        href = "#{@my_ood_url}/pun/sys/dashboard/batch_connect/sys/#{key}"
        icon_html = "<img width=20 title=\"#{key}\" alt=\"#{key}\" src=\"#{@my_ood_url}/pun/sys/dashboard/apps/icon/#{key}/sys/sys\">"
      end
      
      # Return the full HTML string for the link
      "<a style=\"color: black; text-decoration: none;\" target=\"_blank\" href=\"#{href}\">\n  #{icon_html}\n</a>\n"
    end
  end

  # Output a modal for a specific action (e.g., cancel or delete).
  def output_action_modal(action)
    id = "_history#{action.capitalize}"
    form_action = "#{@script_name}/history?action=#{action}"

    <<~HTML
    <div class="modal" id="#{id}" aria-hidden="true" tabindex="-1">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-body" id="#{id}Body">
            (Something wrong)
          </div>
          <div class="modal-footer">
            <form action="#{form_action}" method="post">
              <input type="hidden" name="JobIds" id="#{id}Input">
              <button type="submit" class="btn btn-primary" tabindex="-1">Yes</button>
              <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">No</button>
            </form>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a badge for an action button (e.g., cancel or delete) with a modal trigger.
  def output_action_badge(action)
    modal_target = (action == "delete") ? "info" : "job"
    capitalized_action = action.capitalize
    
    if %w[Cancel Delete].include?(capitalized_action)
      <<~HTML
      <button id="_history#{capitalized_action}Badge" data-bs-toggle="modal" data-bs-target="#_history#{capitalized_action}" class="btn btn-sm btn-danger disabled" disabled>
        #{capitalized_action} #{modal_target} 
        <span id="_history#{capitalized_action}Count" class="badge bg-secondary">0</span>
      </button>
      HTML
    end
  end

  # Output a modal for displaying details of a specific job.
  def output_job_id_modal(job)
    return if job[JOB_KEYS].nil? # If a job has just been submitted, it may not have been registered yet.

    modal_id = "_historyJobId#{job[JOB_ID]}"
    job_details = [
      ["JOB ID",            job[JOB_ID]],
      [JOB_NAME,            job[JOB_NAME]],
      ["Application",       job[JOB_APP_NAME]],
      [JOB_PARTITION,       job[JOB_PARTITION]],
      ["Script Location",   job[HEADER_SCRIPT_LOCATION]],
      ["Script Name",       job[HEADER_SCRIPT_NAME]],
      [JOB_SUBMISSION_TIME, job[JOB_SUBMISSION_TIME]],
      [JOB_STATUS_ID,       job[JOB_STATUS_ID]]
    ]

    html = <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5>Job details</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <table class="table table-striped">
    HTML

    job_details.each do |label, value|
      html += "<tr><td>#{ERB::Util.html_escape(label)}</td><td>#{ERB::Util.html_escape(value)}</td></tr>\n"
    end

    filtered_keys = job[JOB_KEYS] - [JOB_NAME, JOB_PARTITION, JOB_SUBMISSION_TIME, JOB_STATUS_ID]
    filtered_keys.each do |key|
      html += "<tr><td>#{ERB::Util.html_escape(key)}</td><td>#{ERB::Util.html_escape(job[key])}</td></tr>\n"
    end

    html += <<~HTML
            </table>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a modal displaying a job script and a link to load parameters for a specific job.
  def output_job_script_modal(job)
    modal_id = "_historyJobScript#{job[JOB_ID]}"
    job_script = job[SCRIPT_CONTENT]&.gsub(/\r\n|\n/, '<br>')
    job_link = "#{@script_name}#{job[JOB_APP_PATH]}?jobId=#{URI.encode_www_form_component(job[JOB_ID])}"

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-body">
            #{job_script}
          </div>
          <div class="modal-footer">
            <a href="#{job_link}" class="btn btn-primary text-white text-decoration-none">Load Parameters</a>
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Close</button>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a pagination link for history navigation.
  def output_link(is_active, i, rows = 1)
    if is_active
      "<li class=\"page-item active\"><a href=\"#\" class=\"page-link\">#{i}</a></li>\n"
    elsif i == "..."
      "<li class=\"page-item\"><a href=\"#\" class=\"page-link\">...</a></li>\n"
    else
      link = "./history?status=#{@status}&p=#{i}&rows=#{@rows}"
      link += "&filter=#{@filter}" if @filter && !@filter.empty?
      "<li class=\"page-item\"><a href=\"#{link}\" class=\"page-link\">#{i}</a></li>\n"
    end
  end

  # Output a pagination component for navigating through pages of history records.
  def output_pagination(current_page, page_size, rows)
    html = "<nav class=\"mt-1\">\n"
    html += "  <ul class=\"pagination justify-content-center\">\n"

    if current_page == 1
      html += "    <li class=\"page-item disabled\"><a href=\"#\" class=\"page-link\">&laquo;</a></li>\n"
    else
      previous_link = "./history?status=#{@status}&p=#{current_page - 1}&rows=#{@rows}"
      previous_link += "&filter=#{@filter}" if @filter && !@filter.empty?
      html += "    <li class=\"page-item\"><a href=\"#{previous_link}\" class=\"page-link\">&laquo;</a></li>\n"
    end

    if page_size <= 7
      (1..page_size).each do |i|
        html += output_link(current_page == i, i, rows)
      end
    else
      if current_page <= 4
        (1..5).each { |i| html += output_link(current_page == i, i, rows) }
        html += output_link(false, "...")
        html += output_link(false, page_size, rows)
      elsif current_page >= page_size - 3
        html += output_link(false, 1, rows)
        html += output_link(false, "...")
        ((page_size - 4)..page_size).each { |i| html += output_link(current_page == i, i, rows) }
      else
        html += output_link(false, 1, rows)
        html += output_link(false, "...")
        html += output_link(false, current_page - 1, rows)
        html += output_link(true, current_page, rows)
        html += output_link(false, current_page + 1, rows)
        html += output_link(false, "...")
        html += output_link(false, page_size, rows)
      end
    end

    if current_page == page_size
      html += "   <li class=\"page-item disabled\"><a href=\"#\" class=\"page-link\">&raquo;</a></li>\n"
    else
      next_link = "./history?status=#{@status}&p=#{current_page + 1}&rows=#{@rows}"
      next_link += "&filter=#{@filter}" if @filter && !@filter.empty?
      html += "   <li class=\"page-item\"><a href=\"#{next_link}\" class=\"page-link\">&raquo;</a></li>\n"
    end
    
    html += "  </ul>\n"
    html += "</nav>\n"
  end

  # Return the number of Job IDs stored in the database.
  def get_job_size()
    history_db = @conf["history_db"]
    return 0 unless File.exist?(history_db)

    size = 0
    db = PStore.new(history_db)
    db.transaction(true) do
      size = db.roots.size
    end

    return size
  end
  
  # Query a job history based on the target status and filter.
  def get_job_history(target_status, start_index, end_index, filter)
    history_db = @conf["history_db"]
    return [] unless File.exist?(history_db)
    db = PStore.new(history_db)
    
    # Update job status
    if target_status != "completed"
      queried_ids = []
      db.transaction(true) do
        db.roots.reverse[start_index...(end_index+1)].each do |id|
          queried_ids << id if db[id][JOB_STATUS_ID] != JOB_STATUS["completed"]
        end
      end

      if queried_ids != []
        status, error_msg = @scheduler.query(queried_ids, @bin, @bin_overrides, @ssh_wrapper)
        return nil, error_msg if error_msg

        db.transaction do
          status.each do |id, info|
            data = db[id]
            if !data.nil?
              data[JOB_KEYS] = info.keys
              db[id] = data.merge(info)
            end
          end
        end
      end
    end

    jobs = []
    db.transaction(true) do
      db.roots.reverse[start_index...(end_index+1)].each do |id|
        data = db[id]
        next if (data[JOB_STATUS_ID]&.downcase != target_status && target_status != "all")

        info = { JOB_ID => id }
        info.merge!(data)
        next if filter && !info[HEADER_SCRIPT_NAME]&.include?(filter) && !info[JOB_NAME]&.include?(filter)
        
        jobs.push(info)
      end
    end

    [jobs, nil]
  end

  # Output a styled status badge for a job based on its current status.
  def output_status(job_status)
    badge_class, status_text = case job_status
                               when JOB_STATUS["queued"]
                                 ["bg-warning text-dark", "Queued"]
                               when JOB_STATUS["running"]
                                 ["bg-primary", "Running"]
                               when JOB_STATUS["completed"]
                                 ["bg-secondary", "Completed"]
                               else
                                 ["bg-danger", "Unknown"]
                               end
    
    "<span class=\"badge fs-6 #{badge_class}\">#{status_text}</span>\n"
  end
end
