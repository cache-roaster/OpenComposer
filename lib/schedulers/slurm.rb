require 'open3'

class Slurm < Scheduler
  # Submit a job to the Slurm scheduler using the 'sbatch' command.
  # If the submission is successful, it checks for job details using the 'scontrol' command.
  def submit(script_path, bin_path = nil, ssh_wrapper = nil)
    sbatch = find_command_path("sbatch", bin_path)
    command = [ssh_wrapper, sbatch, script_path].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, stderr unless status.success?
    job_id_match = stdout.match(/Submitted batch job (\d+)/)
    return nil, "Job ID not found in output." unless job_id_match

    job_id = job_id_match[1]

    # Fetch job details
    scontrol = find_command_path("scontrol", bin_path)
    command = [ssh_wrapper, scontrol, "show job", job_id].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, stderr unless status.success?

    unless stdout.include?("ArrayTaskId") # Single Job
      return job_id, nil
    else
      # Extract and expand array job IDs
      expanded_ids = stdout.scan(/ArrayTaskId=(\S+)/).flatten.flat_map do |part|
        part.include?('-') ? Range.new(*part.split('-').map(&:to_i)).to_a : [part.to_i]
      end.sort
      return expanded_ids.map { |i| "#{job_id}_#{i}" }, nil # Array Job
    end
  rescue => e
    return nil, e.message
  end

  # Cancel one or more jobs in the Slurm scheduler using the 'scancel' command.
  def cancel(jobs, bin_path = nil, ssh_wrapper = nil)
    scancel = find_command_path("scancel", bin_path)
    command = [ssh_wrapper, scancel, jobs.join(',')].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return status.success? ? nil : stderr
  rescue => e
    return e.message
  end

  # Query the status of one or more jobs in the Slurm system using 'sacct'.
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin_path = nil, ssh_wrapper = nil)
    # https://slurm.schedmd.com/sacct.html
    # BOOT_FAIL     : Job terminated due to launch failure, typically due to a hardware failure.
    # CANCELLED     : Job was explicitly cancelled by the user or system administrator. The job may or may not have been initiated.
    # COMPLETED     : Job has terminated all processes on all nodes with an exit code of zero.
    # DEADLINE      : Job terminated on deadline.
    # FAILED        : Job terminated with non-zero exit code or other failure condition.
    # NODE_FAIL     : Job terminated due to failure of one or more allocated nodes.
    # OUT_OF_MEMORY : Job experienced out of memory error.
    # PENDING       : Job is awaiting resource allocation.
    # PREEMPTED     : Job terminated due to preemption.
    # RUNNING       : Job currently has an allocation.
    # REQUEUED      : Job was requeued.
    # RESIZING      : Job is about to change size.
    # REVOKED       : Sibling was removed from cluster due to other cluster starting the job.
    # SUSPENDED     : Job has an allocation, but execution has been suspended and CPUs have been released for other jobs.
    # TIMEOUT       : Job terminated upon reaching its time limit.
    #
    # The categorization was determined based on the table above and the codes below.
    #  - https://github.com/OSC/ood_core/blob/master/lib/ood_core/job/adapters/slurm.rb
    
    sacct = find_command_path("sacct", bin_path)
    command = [ssh_wrapper, sacct, "--format=JobID,JobName,Submit,Partition,State%20,Start,End -n -j", jobs.join(",")].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, stderr unless status.success?

    info = {}
    stdout.split("\n").each do |line|
      fields = line.split
      id     = fields[0]
      next if id.end_with?(".batch", ".extern")

      # Some information may not be obtained when `sacct` command runs immediately after submitting a job.
      # Moreover, if a job is canceled, line.split.size is more than the number of formats.
      #   e.g. 18257 2024-10-08T15:00:22 None 2024-10-08T15:23:34 r340 CANCELLED by 1015
      if fields.size >= 7
        status_id = case fields[4]
                    when "BOOT_FAIL", "CANCELLED", "COMPLETED", "DEADLINE", "FAILED", "NODE_FAIL", "OUT_OF_MEMORY", "REVOKED", "SPECIAL_EXIT", "TIMEOUT"
                      JOB_STATUS["completed"]
                    when "CONFIGURING", "REQUEUED", "RESIZING", "PENDING", "PREEMPTED", "SUSPENDED"
                      JOB_STATUS["queued"]
                    when "COMPLETING", "RUNNING", "STOPPED"
                      JOB_STATUS["running"]
                    else
                      nil
                    end

        info[id] = {
          JOB_NAME            => fields[1],
          JOB_SUBMISSION_TIME => fields[2].gsub('T', ' '),
          JOB_PARTITION       => fields[3],
          JOB_STATUS_ID       => status_id,
          "Start Time"        => fields[5].gsub('T', ' '),
          "End Time"          => fields[6].gsub('T', ' ')
        }
      else
        info[id] = {
          JOB_NAME    	      => nil,
          JOB_SUBMISSION_TIME => fields[2].gsub('T', ' '),
          JOB_PARTITION       => nil,
          JOB_STATUS_ID       => nil,
          "Start Time"        => fields[5] ? fields[5].gsub('T', ' ') : nil,
          "End Time"          => fields[6] ? fields[6].gsub('T', ' ') : nil
        }
      end
    end

    return info, nil
  rescue => e
    return nil, e.message
  end
end
