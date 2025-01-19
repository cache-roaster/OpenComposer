require 'open3'

class Pbs < Scheduler
  # Submit a job to PBS using the 'qsub' command.
  def submit(script_path, job_name = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    init_bash_path = "/usr/share/Modules/init/bash"
    init_bash = "source #{init_bash_path};" if File.exist?(init_bash_path) && ssh_wrapper.nil?
    qsub = get_command_path("qsub", bin, bin_overrides)
    option = "-N #{job_name}" unless job_name.empty?
    command = [init_bash, ssh_wrapper, qsub, option, script_path].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    # For a normal job, the output will be "123.opbs".
    job_id_match = stdout.match(/^(\d+)\.opbs$/)
    return job_id_match[1], nil if job_id_match

    # For an array job, the output will be "123[].opbs".
    job_id_match = stdout.match(/^(\d+)\[\]\.opbs$/)
    if job_id_match
      qstat = get_command_path("qstat", bin, bin_overrides)
      command = [ssh_wrapper, qstat, "-t", "#{job_id_match[1]}[]"].compact.join(" ") # "-t" option also shows array jobs.
      stdout, stderr, status = Open3.capture3(command)
      return nil, [stdout, stderr].join(" ") unless status.success?

      job_ids = stdout.lines.map do |line|
        first_column = line.split(/\s+/).first
        first_column if first_column&.match?(/^\d+\[\d+\]$/)
      end.compact
      
      return job_ids, nil
    else
      return nil, "Job ID not found in output."
    end
  rescue => e
    return nil, e.message
  end

  # Cancel one or more jobs in PBS using the 'qdel' command.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    scancel = get_command_path("qdel", bin, bin_overrides)
    command = [ssh_wrapper, scancel, jobs.join(' ')].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return status.success? ? nil : [stdout, stderr].join(" ")
  rescue => e
    return e.message
  end

  # Query the status of one or more jobs in PBS using 'qstat'.
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    # QUEUED  : Waiting for job execution
    # RUNNING : Job running
    # BEGUN   : The array job has at least one subjob running
    # EXITING : Job ending
    # FINISH  : Job End
    # HOLD    : Job Storage
    # EXPIRED : Deleted one of the Array jobs.
    
    qstat = get_command_path("qstat", bin, bin_overrides)
    command = [ssh_wrapper, qstat, "-v -t", jobs.join(" ")].compact.join(" ")
    stdout1, stderr1, status1 = Open3.capture3(command)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?

    # Retrieve completed jobs using the same command with '-H' flag
    # Outputs a list of jobs that were completed within the past 31 days, which is the maximum value.
    command = [ssh_wrapper, qstat, "-v -t -H --hday 31", jobs.join(" ")].compact.join(" ")
    stdout2, stderr2, status2 = Open3.capture3(command)
    return nil, [stdout2, stderr2].join(" ") unless status2.success?
    
    info = {}
    (stdout1 + stdout2).split("\n").each do |line|
      fields = line.split
      id     = fields[0]
      next unless id =~ /^\d/

      status_id = case fields[2]
                  when "FINISH", "EXPIRED"
                    JOB_STATUS["completed"]
                  when "QUEUED", "HOLD"
                    JOB_STATUS["queued"]
                  when "RUNNING", "BEGUN", "EXITING"
                    JOB_STATUS["running"]
                  else
                    nil
                  end

      info[id] = {
        JOB_NAME            => fields[1],
        JOB_PARTITION       => fields[4],
        JOB_STATUS_ID       => status_id,
        "PROJECT"           => fields[3],
        "START_DATE"        => "#{Time.now.year}-#{fields[5].tr("/", "-")} #{fields[6]}",
        "ELAPSE"            => fields[7],
        "TOKEN"             => fields[8],
        "NODE"              => fields[9],
        "MIG"               => fields[10]
      }
    end
    return info, nil
  rescue => e
    return nil, e.message
  end
end
