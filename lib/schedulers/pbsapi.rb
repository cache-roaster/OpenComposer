require 'json'
require 'net/http'
require 'open3'


class GraphQLClient
  def initialize(endpoint = nil, token = nil)
    @endpoint = endpoint || read_endpoint
    @token = token || read_token
  end

  def execute_query(query)
    make_request(query)
  end

  private

  def read_endpoint
    ENV["PBS_API_ENDPOINT"]
  end

  def read_token
    ENV['PBS_API_TOKEN']
  end

  def make_request(query)
    uri = URI(@endpoint)
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{@token}"
    request.body = JSON.generate({ query: query })

    response = http.request(request)
    response.body
  rescue StandardError => e
    puts "Error: #{e.message}"
    exit 1
  end
end


class Pbsapi < Scheduler
  # Submit a job to PBS using the 'qsub' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    qsub = get_command_path("qsub", bin, bin_overrides)
    job_name_option = "-N #{job_name}" if job_name && !job_name.empty?
    command = [ssh_wrapper, qsub, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    # For a normal job, the output will be "123.opbs".
    if (job_id_match = stdout.match(/^(\d+)\..+$/))
      return job_id_match[1], nil
    end

    # For an array job, the output will be "123[].opbs".
    if (job_id_match = stdout.match(/^(\d+)\[\]\..+$/))
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
  rescue Exception => e
    return nil, e.message
  end

  # Delete one or more jobs in PBS using the 'qdel' command.
  def delete(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    qdel = get_command_path("qdel", bin, bin_overrides)
    command = [ssh_wrapper, qdel, jobs.join(' ')].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return status.success? ? nil : [stdout, stderr].join(" ")
  rescue Exception => e
    return e.message
  end

  def map_pbs_state_to_status(state)
    case state
    when 10, 11, 12, 9  # Done, Failed, Deleted, Exiting
      JOB_STATUS["completed"]
    when 0, 1, 2, 3, 5, 14  # Queued, Waiting, DependHeld, Held, StagingIn, Unlicensed
      JOB_STATUS["queued"]
    when 6, 7, 8  # StagingOut, Running, Suspended
      JOB_STATUS["running"]
    when 4  # StagingFail - treating as completed with failure
      JOB_STATUS["completed"]
    when 13  # Moved - treating as queued since it's transitioning
      JOB_STATUS["queued"]
    else
      nil
    end
  end

  # Query the status of one or more jobs in PBS using GraphQL API
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    job_query = <<~GRAPHQL
    query myJobList {
      jobs(orderBy: J_JOBID_ASC, filter: {withHistoryJobs:true}) {
        edges {
          node {
            jobId
            name
            queue {
              name
            }
            status {
              state
            }
          }
        }
      }
    }
    GRAPHQL

    client = GraphQLClient.new
    response = client.execute_query(job_query)
    data = JSON.parse(response)
    job_list = data.dig('data', 'jobs', 'edges') || []

    info = {}
    job_list.each do |edge|
      job_node = edge['node']
      job_id_fqdn = job_node['jobId']
      if match = job_id_fqdn.match(/^(\d+)\./)
        job_id = match[1]
      else
        raise "Cannot find job ID, no match from regex"
      end

      # Initialize job info hash
      info[job_id] ||= {}

      # Extract job details
      info[job_id][JOB_NAME] = job_node['name']
      info[job_id][JOB_PARTITION] = job_node.dig('queue', 'name')

      # Map numeric state to status
      state = job_node.dig('status', 'state')
      info[job_id][JOB_STATUS_ID] = map_pbs_state_to_status(state)
    end

    return info, nil
  rescue Exception => e
    return nil, e.message
  end
end
