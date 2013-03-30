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
    "create" => "Creates a new jiffyBox",
    "start" => "Starts a certain jiffyBox",
    "stop" => "Stops a certain jiffyBox",
    "freeze" => "Freezes a certain jiffyBox",
    "thaw" => "Thaws a certain jiffyBox",
    "delete" => "Deletes a certain jiffyBox"
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
      fail "show -i id"
    elsif action == "start"
      fail "start -i id"
    elsif action == "stop"
      fail "stop [now] -i id"
    elsif action == "thaw"
      fail "thaw -i id"
    elsif action == "create"
      fail "create -n name -d distribution -p planid"
    elsif action == "delete"
      fail "delete -i id"
    else
      fail "No help available for #{action}"
    end
  end

  # HELPERS
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
    puts @@options unless jiffy.respond_to?(action)

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
