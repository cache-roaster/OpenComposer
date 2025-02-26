require 'open3'
require 'csv'

class Fujitsu_tcs < Scheduler
  # Submit a job to the Fujitsu TCS scheduler using the 'pjsub' command.
  # If the submission is successful, it checks for job details using the 'pjstat' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    pjsub = get_command_path("pjsub", bin, bin_overrides)
    job_name_option = "-N #{job_name}" if job_name && !job_name.empty?
    command = [ssh_wrapper, pjsub, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?
    return nil, "Job ID not found in output." unless stdout.match?(/Job (\d+) submitted/)
    
    job_id = stdout.match(/Job (\d+) submitted/)[1]
    pjstat = get_command_path("pjstat", bin, bin_overrides)
    command = [ssh_wrapper, pjstat, "-E --data --choose=jid,jmdl", job_id].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?
    
    # Example 1 : stdout of single job
    # ---
    # H,JOB_ID,MD
    # ,34704010,NM

    # Example 2 : stdout of array job
    # ---
    # H,JOB_ID,MD
    # ,34703955,BU
    # ,34703955[1],BU
    # ,34703955[2],BU
    # ,34703955[3],BU
    # ,34703955[4],BU

    # Parse the pjstat output to determine whether it's a single job or an array job
    rows = CSV.parse(stdout)
    if rows.last[2] == "BU" # Array Job
      return rows[1..-1].map { |row| row[1] }, nil
    else
      return rows[1][1], nil # Single Job
    end
  rescue => e
    return nil, e.message
  end
  
  # Cancel one or more jobs in the Fujitsu TCS scheduler using the 'pjdel' command.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    pjdel = get_command_path("pjdel", bin, bin_overrides)
    command = [ssh_wrapper, pjdel, jobs.join(" ")].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return status.success? ? nil : stderr
  rescue => e
    return e.message
  end

  # Query the status of one or more jobs in the Fujitsu TCS system using 'pjstat'.
  # It retrieves job details and combines information for both active and completed jobs.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    pjstat = get_command_path("pjstat", bin, bin_overrides)
    command = [ssh_wrapper, pjstat, "-s -E --data --choose=jid,jnam,rscg,st,jmdl,ec,pc,sdt,elp,edt", jobs.join(" ")].compact.join(" ")
    # -s: Display additional items (e.g. edt)
    # -E: Display subjob
    # --data: Display in CSV format
    # --choose: Display only the specified items
    #   jid: Job ID/ sub-Job ID
    #   jnam: Job name
    #   rscg: Resource Group
    #   st: Status
    #   jmdl: Job Model
    #   ec: Exit Code
    #   pc: PJM Code
    #   sdt: Start Time
    #   elp: Job Elapse Time
    #   edt: End Time

    stdout1, stderr1, status1 = Open3.capture3(command)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?
    # Example of stdout1 (pjstat -s -E --data --choose=jid,rscg,st 34716159 34716160 34716168 34716168[1] 34716168[2])
    # H,JOB_ID,ACCEPT,RSC_GRP,ST
    # ,34716160,10/11 10:21:35,small,QUE
    # ,34716168,10/11 10:23:03,small,QUE
    # ,34716168[1],10/11 10:23:03,small,QUE
    # ,34716168[2],10/11 10:23:03,small,QUE
    # ---
    # Note that Job 34716159 is not displayed because the job has been completed.

    # Retrieve completed jobs using the same command with '-H' flag
    # Outputs a list of jobs that were completed within the past 365 days, which is the maximum value.
    # If a job was completed before 366 days, it will be displayed as "Queued."
    stdout2, stderr2, status2 = Open3.capture3(command + " -H day=365")
    return nil, [stdout2, stderr2].join(" ") unless status2.success?
    # -H: Display only information about jobs that have completed
    # ---
    # Example of stdout2
    # H,JOB_ID,ACCEPT,RSC_GRP,ST
    # ,34716159,10/11 10:21:31,small,EXT

    info = {}
    csv1 = CSV.new(stdout1, headers: true)
    csv2 = CSV.new(stdout2, headers: true)
    stdout = csv1.to_a.map(&:fields) + csv2.to_a.map(&:fields) # Combine both stdout except headers
    stdout.each do |line|
      # ACC: Job submission has been accepted
      # RJT: Submission has not been accepted
      # QUE: Waiting for job execution
      # RNA: Resources required for job execution are being acquired
      # RNP: Prologue is being executed
      # RUN: Job is being executed
      # RNE: Epilogue is being executed
      # RNO: Waiting for job termination processing to complete
      # SPP: Suspending processing in progress
      # SPD: Already suspended
      # RSM: Resume processing in progress
      # EXT: Job termination processing completed
      # CCL: Ended due to job execution being canceled
      # HLD: Fixed state by user
      # ERR: Fixed state due to error
      
      job_id = line[1]
      info[job_id] = {
        JOB_NAME      => line[2],
        JOB_PARTITION => line[3],
        JOB_STATUS_ID => case line[4]
                         when "RJT", "EXT", "CCL", "ERR"
                           JOB_STATUS["completed"]
                         when "ACC", "QUE", "RNA", "SPP", "SPD", "RSM", "HLD"
                           JOB_STATUS["queued"]
                         when "RNP", "RUN", "RNE", "RNO"
                           JOB_STATUS["running"]
                         else
                           nil
                         end,
        "Status Detail" => line[4],
        "Job Model"     => case line[5]
                           when "NM"
                             "Normal Job"
                           when "ST"
                             "Step Job"
                           when "BU"
                             "Bulk Job"
                           when "MW"
                             "Master-Worker Job"
                           end,
        "Exit Code"   => line[6],
        "PJM Code"    => line[7],
        "Start Time"  => line[8],
        "Elapse Time" => line[9],
        "End Time"    => line[10]
      }
    end
      
    return info, nil
  rescue => e
    return nil, e.message
  end
end
