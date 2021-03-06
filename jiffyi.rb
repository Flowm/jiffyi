#!/usr/bin/env ruby

require 'optparse'
require 'yaml'
require 'json'
require 'uri'
require 'net/https'
require 'net/ssh'

class JiffyActionHandler
  BASE_URL = "https://api.jiffybox.de"

  SUPPORTED_ACTIONS = {
    "list" => "Lists all jiffyBoxes of the account",
    "show" => "Shows informations about a single jiffyBox",
    "select" => "Write the IP of the jiffyBox to '~/.jiffyip'",
    "create" => "Creates a new jiffyBox",
    "start" => "Starts a certain jiffyBox",
    "stop" => "Stops a certain jiffyBox",
    "freeze" => "Freezes a certain jiffyBox",
    "thaw" => "Thaws a certain jiffyBox",
    "delete" => "Deletes a certain jiffyBox",
    "install" => "Creates a new jiffyBox and install something on it",
    "teardown" => "Stops and deletes a certain jiffyBox after runnng a script"
  }

  def initialize(attrs)
    @options = attrs
  end

  # BASIC FUNCTIONS
  def list(options)
    if options.first == "plans"
      json = get "plans"
      json
    elsif options.first == "distributions"
      json = get "distributions"
      json
    else
      json = get "jiffyBoxes"
      json['result']
    end
  end

  def show(options)
    help "show" unless @options[:id]
    json = get "jiffyBoxes", @options[:id]
    json['result']
  end

  def create(options)
    help "show" unless @options[:name] && @options[:planid] && @options[:distribution]
    data = {
      'name' => @options[:name],
      'planid' => @options[:planid],
      'distribution' => @options[:distribution],
      'use_sshkey' => "1"
    }
    json = post data
    json
  end

  def start(options)
    help "start" unless @options[:id]
    exit 1 if protected?(@options[:id])
    json = put "START",@options[:id]
    json
  end

  def stop(options)
    help "stop" unless @options[:id]
    exit 1 if protected?(@options[:id])
    if options.first == "now"
      action = "PULLPLUG"
    else
      action = "SHUTDOWN"
    end
    json = put action,@options[:id]
    json
  end

  def freeze(options)
    help "freeze" unless @options[:id]
    exit 1 if protected?(@options[:id])
    json = put "FREEZE",@options[:id]
    json
  end

  def thaw(options)
    help "thaw" unless @options[:id]
    exit 1 if protected?(@options[:id])
    #TODO: Add Plan for thawing
    json = put "THAW",@options[:id]
    json
  end

  def delete(options)
    help "thaw" unless @options[:id]
    exit 1 if protected?(@options[:id])
    json = del @options[:id]
    json
  end

  def help(action)
    # Dokumentation of the actions - TO BE EXTENDED
    if action.class == Array
      JiffyActionHandler.usage if action.first.nil?
      action = action.first
    end
    if action == "list"
      fail "list <planid,distributions,jiffyBoxes>"
    elsif action == "show"
      fail "show -i ID"
    elsif action == "start"
      fail "start -i ID"
    elsif action == "stop"
      fail "stop [now] -i ID"
    elsif action == "thaw"
      fail "thaw -i ID"
    elsif action == "create"
      fail "create -n NAME -d DISTRIBUTION -p PLANID"
    elsif action == "delete"
      fail "delete -i ID"
    elsif action == "install"
      fail "install -n NAME -d DISTRIBUTION -p PLANID [PRESET ...]"
    elsif action == "teardown"
      fail "teardown -i ID"
    else
      fail "No help available for #{action}"
    end
  end

  # EXTENDED FUNCTIONS
  def install(options)
    # Do a complete install of a new jiffyBox (create, start and execute specified scripts)
    # Creation
    help "install" unless @options[:name] && @options[:planid] && @options[:distribution]
    json = create []
    # Workaround for strange network configuration errors
    fail "No valid response recived" unless (json['messages'].class == Array)
    fail "Creation of the Jiffybox wasn't successful" unless
      (json['messages'].length == 0 ||
       json['messages'][0]['message'].match("Netzwerk-Konfiguration"))
    @options[:id] = json['result']['id']

    # Get the jiffyBox running
    begin
      sleep(2)
      json = show []
      case json['status']
      when "CREATING"
        puts "Waiting for creation"
        sleep(10)
      when "READY"
        if json['running'] == false
          start []
          puts "Starting"
        end
      when "UPDATING"
        puts "Waiting for update"
        sleep(5)
      else
        fail "Unknown State of Jiffybox: #{json['status']}"
      end
    end while (json['status'] != "READY" || json['running'] != true)
    puts "Jiffybox now up and running!"
    @ip = json['ips']['public'].first

    # Install the JiffyBox
    # cd to the directory where the programm itself and (hopefully) the scripts folder is located
    prg = File.expand_path $0
    if File.symlink?(prg)
      prg = File.readlink(prg)
    end
    dir = File.dirname(prg)
    Dir.chdir(dir)
    fail "Could not locate scripts folder" unless File.exists?("scripts")
    Dir.mkdir(".tmp") unless File.exists?(".tmp")

    prepare_ssh_cm(dir)

    # Execute the scripts
    exec("mkdir -p install")
    preset = options
    preset.unshift("all")
    preset.each do |name|
      puts "Executing install_#{name}"
      file = Dir.entries('scripts/').detect {|f| f.match /^install_#{name}$/}
      if File.exists?("scripts/#{file}")
        system("scp #{@sshopts} scripts/#{file} root@#{@ip}:install/") ||
          fail("Could not copy file")
        exec("install/#{file}")
      end
    end
    puts "Jiffybox is now installed! IP: #{@ip}"
  end

  def teardown(options)
    # Stop and delete a given jiffyBox
    help "teardown" unless @options[:id]
    exit 1 if protected?(@options[:id])
    json = stop []
    # Ensure that the jiffyBox is stopped
    fail "No valid response recived" unless (json['messages'].class == Array)
    fail "Deletion of the Jiffybox wasn't successful" unless
        (json['messages'].length == 0 ||
         json['messages'][0]['message'].match("dashalb nicht gestoppt werden"))
    # Delete the jiffyBox
    begin
      json = show []
      case json['status']
        when "READY"
          if json['running'] == false
            delete []
            puts "Deleting"
          end
        when "UPDATING"
          sleep(5)
          puts "Waiting for update"
        when "STOPPING"
          sleep(5)
          puts "Waiting for jiffyBox to stop"
        when "DELETING"
        else
          fail "Unknown State of Jiffybox: #{json['status']}"
      end
    end while (json['status'] != "DELETING")
    "Jiffybox #{@options[:id]} is now being deleted"
  end

  def exec(command)
    # Execute a command on the jiffybox
    help "exec" unless command.class == String
    system("ssh #{@sshopts} root@#{@ip} '#{command}'") ||
          fail("Execution of #{command} failed")
  end

  def select(options)
    # Write the ip of the jiffyBox to '~/.jiffyip' for further use in scripts
    json = show []
    ip = json['ips']['public'].first
    f = File.expand_path("~/.jiffyip")
    File.open(f, 'w+') { |file| file.write(ip) }
    "JiffyBox #{@options[:id]} IP #{ip} saved to #{f}"
  end

  # PLANNED FUNCTIONS
  def runscript(options)
    # Run a specified script on the jiffyBox
  end

  def status(options)
    # Give a nice tabular overview over all jiffyBoxes
  end

  def connect(options)
    # Connect to the jiffyBox via SSH
  end

  # HELPERS
  def prepare_ssh_cm(dir)
    # Trick to get an authenticated ssh session without much effort
    fail "IP of the JiffyBox unknown" unless @ip
    fail "Internal error" unless dir && dir.class == String
    @sshopts = "-o ControlMaster=auto -o ControlPath=#{dir}/.tmp/ssh_mux_%h_%p_%r -o StrictHostKeyChecking=no"
    sleep(10)
    spawn("ssh #{@sshopts} root@#{@ip} sleep 600")
    sleep(5)
  end

  def findjiffy(options)
    # Function to get the JiffyBox with the lowest id
    # or a JiffyBox with a given name
    action = options.shift
    json = get "jiffyBoxes"
    id = nil
    if action == "first"
      json['result'].each_value do |box|
        if id.nil? || id > box['id']
          id = box['id']
        end
      end
    elsif action == "name"
      name = options.shift
      json['result'].each_value do |box|
        if box['name'] == name
          id = box['id']
        end
      end
    end
    id
  end

  private

  def protected?(id)
    # Check if the current jiffyBox is in a list of protected IDs
    @options[:protected_ids].each do |pid|
      if (pid == id)
        warn "JiffyBox #{id} is protected. Aborting"
        return true
      end
    end
    return false
  end

  def get(dest = jiffyBoxes, id = nil)
    if id.nil?
      url = URI.parse("#{BASE_URL}/#{@options[:apitoken]}/v1.0/#{dest}")
    else
      url = URI.parse("#{BASE_URL}/#{@options[:apitoken]}/v1.0/#{dest}/#{id}")
    end
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    response = http.request_get(url.path)
    case response
      when Net::HTTPSuccess     then JSON.parse response.body
    else
      response.error!
    end
  end

  def post(post_args)
    url = URI.parse("#{BASE_URL}/#{@options[:apitoken]}/v1.0/jiffyBoxes")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(url.path)
    req.set_form_data(post_args)
    response = http.request(req)
    case response
      when Net::HTTPSuccess     then JSON.parse response.body
    else
      response.error!
    end
  end

  def put(action, id)
    exit 1 if protected?(@options[:id])
    url = URI.parse("#{BASE_URL}/#{@options[:apitoken]}/v1.0/jiffyBoxes/#{id}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    put = "status=#{action}"
    response = http.request_put(url.path, put)
    case response
      when Net::HTTPSuccess     then JSON.parse response.body
    else
      response.error!
    end
  end

  def del(id)
    exit 1 if protected?(@options[:id])
    url = URI.parse("#{BASE_URL}/#{@options[:apitoken]}/v1.0/jiffyBoxes/#{id}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    response = http.delete(url.path)
    case response
      when Net::HTTPSuccess     then JSON.parse response.body
    else
      response.error!
    end
  end

  def fail(msg)
    $stderr.puts "E: #{msg}"
    exit 1
  end

  def self.usage
    puts @@options
    exit 1
  end

  # CLASS METHODS
  def self.run
    # Parsing the command line options
    attrs = {}
    @@options = OptionParser.new do |opts|
      opts.banner = "Usage: jiffyi <action> [options]"
      opts.separator ""
      opts.separator "Available Actions:"
      JiffyActionHandler::SUPPORTED_ACTIONS.to_a {|k,v| k}.each do |action|
        opts.separator "     %-10s  %-30s" % action
      end
      opts.separator ""
      opts.separator "Options:"
      opts.on("-i ID", "--id ID", "(On every Box specify action) The jiffyBox ID") do |id|
        begin
          attrs[:id] = Integer(id)
        rescue
          fail "ID must be numeric!"
        end
      end
      opts.on("-f", "--first", "(On every Box specify action) Use ID of first jiffyBox available" ) do
        attrs[:first] = true
      end
      opts.on("-n NAME", "--name NAME", "(On create) Name of the jiffyBox") do |name|
        attrs[:name] = name
      end
      opts.on("-d DISTRIBUTION", "--distribution DISTRIBUTION", "(On create) Distribution to be used") do |distribution|
        attrs[:distribution] = distribution
      end
      opts.on("-p PLANID", "--plan PLANID", "(On create or thaw) Plan to be used") do |planid|
        attrs[:planid] = planid
      end
      opts.on("-a APITOKEN", "--apitoken APITOKEN", "The API token supplied by jiffybox.de") do |apitoken|
        attrs[:apitoken] = apitoken
      end
    end
    @@options.parse!

    # Read the default configuration file at ~/.jiffyirc
    configf = {}
    f = File.expand_path("~/.jiffyirc")
    if File.exist?(f)
      begin
        configf = YAML.load(File.read(f))
      rescue => e
        warn "Error loading configuration file #{f}."
        fail e
      end
    end
    # Make sure configf["default"] exists
    configf["default"] ||= {}
    attrs = configf["default"].merge(attrs)

    # Start
    JiffyActionHandler.usage unless ARGV.size >= 1
    action = ARGV.shift
    jiffy = JiffyActionHandler.new attrs
    puts JiffyActionHandler.usage unless jiffy.respond_to?(action)

    # Getting the id if not already given
    if !attrs[:id]
      if attrs[:first]
        attrs[:id] = jiffy.send("findjiffy", ["first"])
      end
      if attrs[:name]
        attrs[:id] = jiffy.send("findjiffy", ["name", attrs[:name]])
      end
    end

    # Execute the command
    puts jiffy.send(action, ARGV)
  end
end

JiffyActionHandler.run
