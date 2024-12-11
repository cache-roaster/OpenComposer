# This class is a superclass for job schedulers, which provides an
# interface to interact with different scheduling systems.
class Scheduler
  # Submit a job to the scheduler.
  # @param script_path [String] the path to the job script.
  # @param bin_path [String] the path to the directory where a binary is located (optional).
  # @param ssh_wrapper [String] the SSH wrapper. This is used when the local server does not have a job scheduler (optional).
  # @return [Array<String, String>] job id and error message. If successful, the error message is nil; otherwise, the job id is nil.
  def submit(script_path, bin_path = nil, ssh_wrapper = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  # Cancel one or more jobs.
  # @param job_ids [Array] an array of job IDs to be canceled.
  # @param bin_path [String] Same as submit().
  # @param ssh_wrapper [String] Same as submit().
  # @return [String] error message. If successful, the error message is nil.
  def cancel(job_ids, bin_path = nil, ssh_wrapper = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  # Query the status of one or more jobs.
  # @param job_ids [Array] an array of job IDs to be queried.
  # @param bin_path [String] Same as submit().
  # @param ssh_wrapper [String] Same as submit().
  # @return [Array<Hash>] a hash array containing job status and error message.
  #         Example: {JOB_NAME => "foo", JOB_SUBMISSION_TIME => "2024-09-21 15:59:14", JOB_PARTITION => "GH100", JOB_STATUS_ID => JOB_STATUS["completed"]}
  #         Status can be one of: JOB_STATUS["completed"], JOB_STATUS["queued"], JOB_STATUS["running"].
  #         Additional key-value pairs will be displayed in a modal on the History page when clicking on the job ID.
  def query(job_ids, bin_path = nil, ssh_wrapper = nil)
    raise NotImplementedError, "This method should be overridden by a subclass"
  end

  private

  # Attempt to find the full path to a given command.
  # If a custom bin_path is provided, it checks for the command in that directory.
  # If the command exists in the provided bin_path, it returns the full path.
  # Otherwise, it falls back to using just the command name, assuming it is in the system's PATH.
  #
  # @param command_name [String] the name of the command to find (e.g. "sbatch").
  # @param bin_path [String] Same as submit().
  # @return [String] the full path to the command if found, or the command name if not.
  def find_command_path(command_name, bin_path = nil)
    command_path = bin_path ? File.join(bin_path, command_name) : command_name
    File.exist?(command_path) ? command_path : command_name
  end
end
